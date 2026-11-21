/*
  FOOD-109 — роль inspector и права доступа.
  Запускать администратором БД (например, postgres).
  Схема проекта из предоставленного архива: egorov_food.
*/

-- Создать роль, если её ещё нет; если есть — задать актуальный пароль.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'inspector'
    ) THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END
$$;

-- Доступ к схеме проекта и всем уже существующим объектам.
GRANT ALL PRIVILEGES ON SCHEMA egorov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA egorov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA egorov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA egorov_food TO inspector;

-- UUID-функция вызывается через DEFAULT exts.uuid_generate_v4().
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA exts TO inspector;

-- Системные каталоги доступны для чтения; явно не отзываем стандартные права.
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog TO inspector;

-- Права на объекты, которые владелец создаст в этих схемах в будущем.
-- Эти команды должны выполняться именно владельцем объектов (обычно egorov).
ALTER DEFAULT PRIVILEGES IN SCHEMA egorov_food
    GRANT ALL PRIVILEGES ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA egorov_food
    GRANT ALL PRIVILEGES ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA egorov_food
    GRANT ALL PRIVILEGES ON ROUTINES TO inspector;