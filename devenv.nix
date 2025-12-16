{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  # https://qdrant.github.io/fastembed/examples/Supported_Models/
  env.EMBEDDING_MODEL = "BAAI/bge-small-en-v1.5";
  # depends on EMBEDDING_MODEL
  env.EMBEDDING_DIMS = 384;

  # see postgres service below
  env.POSTGRES_ADMIN = "admin";
  env.POSTGRES_USER = "admin";
  env.POSTGRES_PASSWORD = "test";
  env.POSTGRES_ADDRESS = "127.0.0.1";
  env.POSTGRES_PORT = "5432";

  env.OPENSEARCH_ADDRESS = "127.0.0.1";
  env.OPENSEARCH_PORT = "9200";
  env.INDEX_NAME = "test_datacite";

  env.CELERY_BROKER_URL = "redis://127.0.0.1:6379/0";
  env.CELERY_RESULT_BACKEND = "redis://127.0.0.1:6379/0";
  env.CELERY_BATCH_SIZE = 250;

  # https://devenv.sh/languages/
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

  languages = {
    javascript = {
      enable = true;
      npm.enable = true;
    };
    typescript.enable = true;
  };

  packages = [
    pkgs.nodejs-slim_24
    pkgs.nodePackages.typescript-language-server
    pkgs.nodePackages.prettier
    pkgs.secretspec
  ];

  # enterShell = ''
  #   # install from uv.lock https://github.com/astral-sh/uv/issues/14568
  #   uv export --frozen -o requirements.txt
  #   uv pip install -r requirements.txt
  #   uv pip install -e .
  #   uv pip install -e "./data-commons-search[agent]"
  # '';

  # https://devenv.sh/processes/

  # transform restapi
  processes.transform = {
    exec = "fastapi run --host 127.0.0.1 transform.py --port 8080";
    cwd = "./src";
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

  # https://devenv.sh/services/
  services.redis = {
    enable = true;
    extraConfig = ''
      bind * -::*
      protected-mode no
      dir ./redis-data
    '';
  };

  # # celery as task worker
  # processes.celery = {
  #   # https://docs.celeryq.dev/en/latest/internals/reference/celery.concurrency.solo.html
  #   # consider performance, `solo` is single thread pool, no async gain for performance.
  #   exec = "celery -A src.tasks worker -E --pool=solo --loglevel=INFO";
  #   cwd = "./";
  #   process-compose = {
  #     depends_on.redis.condition = "process_healthy";
  #     readiness_probe = {
  #       exec.command = ''
  #         celery -A src.tasks status
  #       '';
  #       initial_delay_seconds = 2;
  #       period_seconds = 12;
  #       timeout_seconds = 10;
  #       success_threshold = 1;
  #       failure_threshold = 5;
  #     };
  #   };
  # };

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_17;
    # TODO: somehow postgres user can not added
    # initialScript = ''
    #   CREATE ROLE postgres SUPERUSER;
    # '';
    listen_addresses = "127.0.0.1";
    port = 5432;
    initialDatabases = [
      {
        name = "admin";
        user = "admin";
        pass = "test";
      }
    ];
  };

  services.opensearch = {
    enable = true;
    settings = {
      cluster.name = "opensearch";
      discovery.type = "single-node";
      network.host = "127.0.0.1";
      http.port = "9200";
      transport.port = "9300";
    };
  };

  # install required python dependencies
  # dependencies are managed by a `uv.lock` to conform with all submodules in python
  tasks."python:install-dependencies" = {
    exec = "uv export --frozen -o requirements.txt && uv pip install --frozen -o requirements.txt";
    cwd = ".";
    # before = [
    #   "devenv:tasks:python:install-data-commons-search"
    #   "devenv:tasks:python:install-metadata-warehouse"
    # ];
  };

  tasks."python:install-data-commons-search" = {
    exec = "uv pip install -e ./data-commons-search/";
    cwd = ".";
    # before = [
    #   "devenv:processes:data-commons-search"
    # ];
  };

  tasks."python:install-metadata-warehouse" = {
    exec = "uv pip install -e ./metadata-warehouse/";
    cwd = ".";
    # before = [
    #   "devenv:processes:metadata-warehouse"
    # ];
  };

  # data-commons-search service
  # need by data-commons-search
  env.EINFRACZ_API_KEY = config.secretspec.secrets.EINFRACZ_API_KEY;
  env.OPENROUTER_API_KEY = config.secretspec.secrets.OPENROUTER_API_KEY;
  processes.data-commons-search =
    let
      num_works = "6";
      host = "127.0.0.1";
      port = "8082";
      opensearch_url = "127.0.0.1:9200";
      default_llm_model = "einfracz/gpt-oss-120b";
    in
    {
      exec =
        "DEFAULT_LLM_MODEL=${default_llm_model} SERVER_PORT=${port} OPENSEARCH_URL=${opensearch_url}"
        + " "
        + "uv run uvicorn data_commons_search.main:app --host ${host} --port ${port} --workers ${num_works} --log-config logging.yml";
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
  tasks."matchmaker:npm-install" = {
    exec = "npm ci";
    cwd = ".";
    before = [ "devenv:processes:matchmaker-frontend" ];
  };

  processes.matchmaker-frontend =
    let
      # must include 'http' since the value is used for vite proxy.
      backend_url = "http://127.0.0.1:8082";

      # NOTE: don't change
      # the dev port is hardcoded in the matchmaker at vite config. I won't bother to make it customizable.
      frontend_port = "5173";
    in
    {
      exec = "VITE_BACKEND_API_URL=${backend_url} VITE_DEV_PORT=${frontend_port} npm run dev";
      cwd = "./matchmaker/";
      process-compose = {
        depends_on.data-commons-search.condition = "process_healthy";
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

  tasks."app:cleanup:redis" = {
    exec = ''
      echo "Redis server stopped, cleaning up..."
      rm -rf ./redis-data
    '';
    after = [ "devenv:processes:redis" ];
  };

  # NOTE: the lift-cycle of full example data creating and clear is:
  # 1. create db "admin" -> import db entries from dump.sql -> create opensearch indexing ->
  # -> indexing to db (in production this runs async in another thread) -> delete db "admin" -> back to '1'

  # --- postgres
  # TODO: and run transform script
  tasks = {
    "app:psql:import" = {
      exec = "psql -U admin admin < dump.sql";
      status = "db-needs-import";
    };
  };

  # index opensearch
  tasks."app:opensearch:creat_index" = {
    exec = "uv run create_index.py";
    cwd = "./scripts/opensearch_data/create_index.py";
  };

  # XXX: not ideal to use my local user name, should create a `postgres` user for this purpose.
  tasks."app:psql:clean" = {
    exec = ''
      psql -U jyu -d postgres -c "DROP DATABASE admin;"
      psql -U jyu -d postgres -c 'CREATE DATABASE admin OWNER admin;'
    '';
  };
}
