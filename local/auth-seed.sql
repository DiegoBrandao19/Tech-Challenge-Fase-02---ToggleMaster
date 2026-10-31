-- Semeia uma chave de serviço FIXA (apenas para ambiente local/docker-compose),
-- assim o evaluation-service sobe sem passo manual. Hash = SHA-256 da chave em texto plano.
INSERT INTO api_keys (name, key_hash)
VALUES ('evaluation-service-local', encode(sha256('tm_key_local_dev_evaluation_service'::bytea), 'hex'))
ON CONFLICT (key_hash) DO NOTHING;
