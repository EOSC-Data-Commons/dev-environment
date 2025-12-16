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

  enterShell = '''';

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

  # https://devenv.sh/services/
  services.redis = {
    enable = true;
    extraConfig = ''
      bind * -::*
      protected-mode no
      dir ./redis-data
    '';
  };

  tasks."setup:python:data-commons-search" = {
    exec = "uv pip install -e ./data-commons-search[agent]";
    cwd = ".";
  };

  tasks."setup:python:metadata-warehouse" = {
    exec = "uv pip install -e ./metadata-warehouse/";
    cwd = ".";
  };

  tasks."clean:python" = {
    exec = ''
      rm -rf ./.devenv/state/venv/
      rm -f ./requirements.txt
    '';
    cwd = ".";
  };

  # celery as task worker
  processes.metadata-warehouse-tasks = {
    # https://docs.celeryq.dev/en/latest/internals/reference/celery.concurrency.solo.html
    # consider performance, `solo` is single thread pool, no async gain for performance.
    exec = "celery -A tasks worker -E --pool=solo --loglevel=INFO";
    cwd = "./metadata-warehouse/src";
    process-compose = {
      depends_on.redis.condition = "process_healthy";
      readiness_probe = {
        # this is ugly because metadata-warehouse did not properly manage the python package structure.
        exec.command = ''
          cd ./metadata-warehouse/src && celery -A tasks status && cd ../..
        '';
        initial_delay_seconds = 2;
        period_seconds = 12;
        timeout_seconds = 10;
        success_threshold = 1;
        failure_threshold = 5;
      };
    };
  };

  # https://devenv.sh/processes/
  # transform restapi
  processes.metadata-warehouse-transform-api = {
    exec = "fastapi run --host 127.0.0.1 transform.py --port 8080";
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

  # data-commons-search service
  # need by data-commons-search
  env.EINFRACZ_API_KEY = config.secretspec.secrets.EINFRACZ_API_KEY;
  env.OPENROUTER_API_KEY = config.secretspec.secrets.OPENROUTER_API_KEY;
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
    exec = "rm -rf ./node_modules/";
    cwd = ".";
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
      exec = ''
        export VITE_BACKEND_API_URL=${backend_url} 
        export VITE_DEV_PORT=${frontend_port} 
        npm run dev'';
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

  tasks."clean:redis" = {
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
    "db-setup:psql:import" = {
      exec = "psql -U admin admin < dump.sql";
      status = "db-needs-import";
    };
  };

  # index opensearch
  tasks."db-setup:opensearch:create-index" = {
    exec = "python create_index.py";
    cwd = "./metadata-warehouse/scripts/opensearch_data/";
    after = [ "db-setup:psql:import" ];
  };

  tasks."clean:psql" = {
    exec = ''
      psql -U $USER -d postgres -c "DROP DATABASE admin;"
      psql -U $USER -d postgres -c 'CREATE DATABASE admin OWNER admin;'
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
}
