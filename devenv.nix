{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  dotenv.enable = true;
  dotenv.filename = [ ".env.development" ];
  process.manager.implementation = "process-compose";

  # devenv recommond to use secretspec, which not enabled here for simplicity.
  # env.EINFRACZ_API_KEY = config.secretspec.secrets.EINFRACZ_API_KEY;
  # env.OPENROUTER_API_KEY = config.secretspec.secrets.OPENROUTER_API_KEY;

  # https://qdrant.github.io/fastembed/examples/Supported_Models/
  env.EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
  # depends on EMBEDDING_MODEL
  env.EMBEDDING_DIMS = 384;

  env.OPENSEARCH_ADDRESS = "127.0.0.1";
  env.OPENSEARCH_PORT = "9200";
  env.INDEX_NAME = "test_datacite";

  env.CELERY_BROKER_URL = "redis://127.0.0.1:6379/0";
  env.CELERY_RESULT_BACKEND = "redis://127.0.0.1:6379/0";
  env.CELERY_BATCH_SIZE = 250;

  packages = [
    pkgs.nodejs-slim_24
    pkgs.typescript-language-server
    pkgs.prettier
    pkgs.cargo-dist
    pkgs.grpc-health-probe
    pkgs.openssl # need by coordinator
  ];

  languages.rust.enable = true;

  languages.python = {
    enable = true;
    version = "3.12.12";
    venv = {
      enable = true;
    };
    uv = {
      enable = true;
      sync = {
        enable = true;
        allPackages = true;
      };
    };
  };

  enterShell = "";

  languages = {
    javascript = {
      enable = true;
      npm.enable = true;
    };
    typescript.enable = true;
  };
  # https://devenv.sh/services/
  services.redis = {
    enable = true;
    extraConfig = ''
      bind * -::*
      protected-mode no
      dir ./redis-data
    '';
  };

  tasks."clean:python" = {
    exec = ''
      rm -rf ./.devenv/state/venv/
    '';
    cwd = ".";
  };

  # celery as task worker
  processes.metadata-warehouse-tasks =
    let
      postgres_admin = "admin";
      postgres_user = "admin";
      postgres_password = "test";
      postgres_address = "127.0.0.1";
      postgres_port = "5432";
      postgres_db = "dataset";
    in
    {
      # https://docs.celeryq.dev/en/latest/internals/reference/celery.concurrency.solo.html
      # consider performance, `solo` is single thread pool, no async gain for performance.
      exec = ''
        export POSTGRES_ADMIN=${postgres_admin}
        export POSTGRES_USER=${postgres_user}
        export POSTGRES_PASSWORD=${postgres_password}
        export POSTGRES_ADDRESS=${postgres_address}
        export POSTGRES_PORT=${postgres_port}
        export POSTGRES_DB=${postgres_db}
        celery -A tasks worker -E --pool=solo --loglevel=INFO
      '';
      cwd = "./metadata-warehouse/src";
      process-compose = {
        depends_on.redis.condition = "process_healthy";
        readiness_probe = {
          # this is ugly because metadata-warehouse did not properly manage the python package structure.
          exec.command = ''
            cd ./metadata-warehouse/src && celery -A tasks status && cd ../..
          '';
          initial_delay_seconds = 2;
          period_seconds = 60;
          timeout_seconds = 100;
          success_threshold = 1;
          failure_threshold = 20;
        };
      };
    };

  # https://devenv.sh/processes/
  # transform restapi
  processes.metadata-warehouse-transform-api =
    let
      postgres_admin = "admin";
      postgres_user = "admin";
      postgres_password = "test";
      postgres_address = "127.0.0.1";
      postgres_port = "5432";
      postgres_db = "dataset";
    in
    {
      exec = ''
        export POSTGRES_ADMIN=${postgres_admin}
        export POSTGRES_USER=${postgres_user}
        export POSTGRES_PASSWORD=${postgres_password}
        export POSTGRES_ADDRESS=${postgres_address}
        export POSTGRES_PORT=${postgres_port}
        export POSTGRES_DB=${postgres_db}
        fastapi run --host 127.0.0.1 transform.py --port 8080
      '';
      cwd = "./metadata-warehouse/src";
      process-compose = {
        readiness_probe = {
          exec.command = ''
            if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/health | grep -q 200; then
              exit 0
            else
              echo "API not ready yet..." 2>&1
              exit 1
            fi
          '';
          initial_delay_seconds = 2;
          period_seconds = 10;
          timeout_seconds = 4;
          success_threshold = 1;
          failure_threshold = 5;
        };
      };
    };

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_17;
    listen_addresses = "127.0.0.1";
    port = 5432;
    initialDatabases = [
      {
        name = "dataset";
        user = "admin";
        pass = "test";
      }
    ];
  };

  services.opensearch =
    let
      # need this for opensearch==2.19.0, others all has api problem.
      oldPkgs = import (fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/nixos-25.11.tar.gz";
      }) { };
    in
    {
      enable = true;
      package = oldPkgs.opensearch;
      settings = {
        cluster.name = "opensearch";
        discovery.type = "single-node";
        network.host = "127.0.0.1";
        http.port = "9200";
        transport.port = "9300";
      };
    };

  # data-commons-search service
  # need by data-commons-search
  processes.data-commons-search =
    let
      num_works = "2";
      host = "127.0.0.1";
      port = "8082";
      opensearch_url = "127.0.0.1:9200";
      default_llm_model = "einfracz/gpt-oss-120b";
    in
    {
      exec = ''
        export DEFAULT_LLM_MODEL=${default_llm_model} 
        export SERVER_PORT=${port}
        export OPENSEARCH_URL=${opensearch_url}
        uvicorn data_commons_search.main:app --host ${host} --port ${port} --workers ${num_works} --log-config logging.yml
      '';
      cwd = "./data-commons-search/";
      process-compose = {
        depends_on.opensearch.condition = "process_healthy";
        readiness_probe = {
          exec.command = ''
            if curl -s -o /dev/null -w "%{http_code}" http://${host}:${port}/ | grep -q 200; then
              exit 0
            else
              echo "API not ready yet..." 2>&1
              exit 1
            fi
          '';
          initial_delay_seconds = 2;
          period_seconds = 10;
          timeout_seconds = 4;
          success_threshold = 1;
          failure_threshold = 5;
        };
      };
    };

  # install js dependencies in the project folder, start frontend process (run dev) in the matchmaker folder
  # NOTE: this is already done when enter the devenv by `npm.enable = true;`
  # This task is meant to be run after clean without leaving the session.
  tasks."setup:npm" = {
    exec = "npm ci";
    cwd = ".";
  };

  # symmetry clean up the npm
  tasks."clean:npm" = {
    exec = ''
      rm -rf ./node_modules/
    '';
    cwd = ".";
  };

  processes.coordinator = {
    exec = "cargo run --bin rp-real";
    cwd = "./matchmaker/req-packager/";
    process-compose = {
      readiness_probe = {
        exec.command = ''
          # `grpc-health-probe -addr=[::1]:50051 -service=coordinator.v1.DataplayerService`
          # command probe for a service, but here I assume when coordinator running all services are good.
          # in the production deployment, I should probe every sub services and give extensive log.
          OUTPUT=$(grpc-health-probe -addr=[::1]:50051 2>&1)

          if echo "$OUTPUT" | grep -q SERVING; then
            exit 0
          else
            echo "Frontend not ready yet" >&2
            echo "$OUTPUT" >&2
            exit 1
          fi
        '';
        initial_delay_seconds = 2;
        period_seconds = 10;
        timeout_seconds = 4;
        success_threshold = 1;
        failure_threshold = 5;
      };
    };
  };

  processes.matchmaker =
    let
      # must include 'http' since the value is used for vite proxy.
      search_api_url = "http://127.0.0.1:8082";
      player_api_url = "https://dev1.player.eosc-data-commons.eu";

      # NOTE: don't change
      # the dev port is hardcoded in the matchmaker at vite config. I won't bother to make it customizable.
      frontend_port = "5173";
    in
    {
      exec = ''
        export SEARCH_API_URL=${search_api_url} 
        export PLAYER_API_URL=${player_api_url} 
        export PORT=${frontend_port} 
        tsx server.ts'';
      cwd = "./matchmaker/";
      process-compose = {
        depends_on.data-commons-search.condition = "process_healthy";
        depends_on.coordinator.condition = "process_healthy";
        readiness_probe = {
          exec.command = ''
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:${frontend_port}/ | grep -q 200; then
              exit 0
            else
              echo "Frontend not ready yet (status: $STATUS)" >&2
              exit 1
            fi
          '';
          initial_delay_seconds = 2;
          period_seconds = 10;
          timeout_seconds = 4;
          success_threshold = 1;
          failure_threshold = 5;
        };
      };
    };

  # --- redis
  # https://devenv.sh/tasks/
  tasks."app:redis-data" = {
    exec = "mkdir -p redis-data";
    before = [ "devenv:processes:redis" ];
  };

  tasks."clean:redis" = {
    exec = ''
      echo "Redis server stopped, cleaning up..."
      rm -rf ./redis-data
    '';
    after = [ "devenv:processes:redis" ];
  };

  # NOTE: the lift-cycle of manually full example data creating and clear is:
  # 1. create db "admin" -> import db entries from dump.sql -> create opensearch indexing ->
  # -> indexing to db (in production this runs async in another thread) -> delete db "admin" -> back to '1'

  # --- postgres
  tasks."db-import:dump-datasetdb" = {
    exec = "psql -U admin dataset < datasetdb_dump_2026_04_10.sql";
    status = "datasetdb-needs-dump";
    # before = [ "db-import:dump-transform-index" ];
    before = [ "db-import:create-index" ];
  };

  tasks."db-import:dump-transform-index" = {
    exec = "psql -U admin dataset < datasetdb_dump_with_transform_2026_04_10.sql";
    status = "transform-db-needs-dump";
    before = [ "db-import:create-index" ];
  };
  #
  # tasks."db-import:dump-filedb" = {
  #   exec = "psql -U admin dataset < filedb_dump_2026_04_10.sql";
  #   status = "filedb-needs-dump";
  #   # before = [ "db-import:create-index" ];
  # };

  # index opensearch
  tasks."db-import:create-index" =
    let
      venvPython = "$DEVENV_ROOT/.devenv/state/venv/bin/python";
    in
    {
      exec = ''
        ${venvPython} create_index.py
      '';
      # exec = ''python -c "import site; print(site.getsitepackages())"'';
      cwd = "./metadata-warehouse/scripts/opensearch_data/";
      before = [ "db-import:indexing" ];
    };

  # import three small data repos
  tasks."db-import:indexing" =
    let
      venvPython = "$DEVENV_ROOT/.devenv/state/venv/bin/python";
    in
    {
      exec = ''
        ${venvPython} repo-index.py indexing https://api.archives-ouvertes.fr/oai/hal
        ${venvPython} repo-index.py indexing https://phys-techsciences.datastations.nl/oai
        ${venvPython} repo-index.py indexing https://archaeology.datastations.nl/oai
        # ${venvPython} repo-index.py indexing https://dabar.srce.hr/oai/
        # ${venvPython} repo-index.py indexing https://ssh.datastations.nl/oai
        # ${venvPython} repo-index.py indexing https://www.swissubase.ch/oai-pmh/v1/oai
        # ${venvPython} repo-index.py indexing https://lifesciences.datastations.nl/oai
        # ${venvPython} repo-index.py indexing https://dataverse.nl/oai
        # ${venvPython} repo-index.py indexing https://demo.onedata.org/oai_pmh
      '';
    };

  tasks."clean:db" = {
    exec = ''
      psql -U $USER -d postgres -c "DROP DATABASE dataset;"
      psql -U $USER -d postgres -c 'CREATE DATABASE dataset OWNER admin;'
    '';
  };

  tasks."purge:all" = {
    exec = ''
      rm -rf ./.devenv/
      rm -rf ./node_modules/
      rm -rf ./redis-data/
      rm -f ./requirements.txt
    '';
    cwd = ".";
  };

  tasks."dev:uv-sync" = {
    exec = ''
      rm -f ./uv.lock
      uv sync
    '';
  };
}
