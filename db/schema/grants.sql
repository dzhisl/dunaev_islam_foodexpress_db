-- Пользователь inspector и права (FOOD-109)
-- Запускать после восстановления бэкапа.

-- 1. Роль inspector с паролем NetoSQL2025
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END
$$;

-- 2. Подключение к текущей БД
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO inspector', current_database());
END
$$;

-- 3. Все права на схему dunaev_food
GRANT ALL PRIVILEGES ON SCHEMA dunaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA dunaev_food TO inspector;   -- таблицы и представление
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA dunaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA dunaev_food TO inspector;   -- функции и процедуры

-- enum типы
DO $$
DECLARE
    t record;
BEGIN
    FOR t IN SELECT typname FROM pg_type
             WHERE typnamespace = 'dunaev_food'::regnamespace AND typtype = 'e'
    LOOP
        EXECUTE format('GRANT USAGE ON TYPE dunaev_food.%I TO inspector', t.typname);
    END LOOP;
END
$$;

-- права на новые объекты
ALTER DEFAULT PRIVILEGES IN SCHEMA dunaev_food GRANT ALL ON TABLES    TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA dunaev_food GRANT ALL ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA dunaev_food GRANT ALL ON ROUTINES  TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA dunaev_food GRANT USAGE ON TYPES   TO inspector;

-- 4. Схема exts для uuid_generate_v4()
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA exts TO inspector;

-- 5. Системные каталоги
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog         TO inspector;
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO inspector;
GRANT SELECT ON pg_catalog.pg_tables, pg_catalog.pg_namespace, pg_catalog.pg_class,
                pg_catalog.pg_type, pg_catalog.pg_enum, pg_catalog.pg_constraint,
                pg_catalog.pg_proc, pg_catalog.pg_extension, pg_catalog.pg_roles
      TO inspector;

-- 6. search_path для inspector
DO $$
BEGIN
    EXECUTE format('ALTER ROLE inspector IN DATABASE %I SET search_path = dunaev_food, exts, public',
                   current_database());
END
$$;
