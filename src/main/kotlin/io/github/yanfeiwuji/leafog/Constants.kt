package io.github.yanfeiwuji.leafog

/**
 * @author  yanfeiwuji
 * @date  2023/12/16 12:57
 */
const val PGRST_JWT_SECRET_KEY = "pgrst.jwt_secret"
const val PGRST_DB_SCHEMAS_KEY = "pgrst.db_schemas"
val PROTECTED_SCHEMAS = listOf("auth", "postgrest", "public")

const val KEYCLOAK_REALM_NAME = "leafog"