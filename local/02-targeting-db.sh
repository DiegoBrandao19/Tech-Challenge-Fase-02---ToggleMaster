#!/bin/bash
# Roda dentro do postgres-flags: cria o 2º banco (targeting_db) na mesma instância.
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE targeting_db"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d targeting_db -f /sql/targeting-init.sql
