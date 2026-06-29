-- Initialise the Solid Cache / Solid Queue / Solid Cable logical databases.
-- These databases live on the same PostgreSQL cluster as the primary database
-- and are created once when the accessory container starts for the first time.

CREATE DATABASE tech_notes_production_cache;
CREATE DATABASE tech_notes_production_queue;
CREATE DATABASE tech_notes_production_cable;