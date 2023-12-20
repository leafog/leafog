package io.github.yanfeiwuji.leafog

import com.fasterxml.jackson.databind.ObjectMapper
import io.quarkus.hibernate.orm.panache.kotlin.PanacheCompanionBase
import io.quarkus.hibernate.orm.panache.kotlin.PanacheEntityBase
import io.quarkus.runtime.Startup
import io.smallrye.mutiny.Uni
import io.smallrye.mutiny.infrastructure.Infrastructure
import jakarta.enterprise.context.ApplicationScoped
import jakarta.inject.Inject
import jakarta.persistence.Entity
import jakarta.persistence.EntityManager
import jakarta.persistence.Id
import jakarta.transaction.Transactional
import jakarta.ws.rs.GET
import jakarta.ws.rs.Path
import org.eclipse.microprofile.config.ConfigProvider
import org.eclipse.microprofile.config.inject.ConfigProperty
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient
import org.eclipse.microprofile.rest.client.inject.RestClient
import org.keycloak.admin.client.Keycloak
import org.keycloak.representations.idm.*
import org.keycloak.representations.idm.authorization.*

import java.util.function.Function


@Entity
class Conf : PanacheEntityBase {


    companion object : PanacheCompanionBase<Conf, String> {

    }

    @Id
    lateinit var key: String
    lateinit var value: String
}

@ApplicationScoped
class ConfService {

    fun update(key: String, convert: Function<String, String>) {
        val conf = Conf.findById(key) ?: Conf().also { it.key = key }
        val value = convert.apply(conf.value)
        conf.value = value
        conf.persistAndFlush()
    }

    @Transactional
    fun updateAll(map: Map<String, String>) {
        map.map { (key, value) ->
            (Conf.findById(key) ?: Conf().also { it.key = key }).also {
                it.value = value
            }
        }.forEach {
            it.persist()
        }
        Conf.flush()
    }

    fun findByKey(key: String): Conf {
        return Conf.findById(key) ?: Conf().also { it.key = key }
    }

}

class KeycloakInit {
    companion object {
        val LEAFOG_REALM = RealmRepresentation().apply {
            realm = KEYCLOAK_REALM_NAME
            isEnabled = true
        }

        val MINIO_CLIENT_SCOPE: ClientScopeRepresentation = ClientScopeRepresentation().apply {
            name = "minio"
            attributes = mapOf(
                "consent.screen.text" to "",
                "display.on.consent.screen" to "true",
                "include.in.token.scope" to "true",
                "consent.screen.text" to "",
                "gui.order" to ""
            )
            protocol = "openid-connect"
            protocolMappers = listOf(
                ProtocolMapperRepresentation().apply {
                    name = "minio-policy-mapper"
                    protocolMapper = "oidc-usermodel-attribute-mapper"
                    protocol = "openid-connect"
                    config = mapOf(
                        "user.attribute" to "minioPolicy",
                        "claim.name" to "minio_policy",
                        "jsonType.label" to "String",
                        "id.token.claim" to "true",
                        "access.token.claim" to "true",
                        "userinfo.token.claim" to "true"
                    )
                }
            )
        }

        val MINIO_CLIENT = ClientRepresentation().apply {
            clientId = "minio"
            protocol = "openid-connect"
            isPublicClient = false
            isServiceAccountsEnabled = false
            isStandardFlowEnabled = true
            authorizationServicesEnabled = false
            isAlwaysDisplayInConsole = false

        }

        val KC_SCOPES_SET = listOf(
            "view",
            "map-roles-client-scope",
            "map-roles",
            "configure",
            "manage",
            "map-roles-composite",
            "token-exchange"
        )
            .map {
                ScopeRepresentation().apply {
                    name = it
                }
            }.toSet()

        val ALL_TIME_CLIENT_POLICY = TimePolicyRepresentation().apply {
            name = "all time"
            description = ""
            type = "time"
            logic = Logic.POSITIVE
            decisionStrategy = DecisionStrategy.UNANIMOUS
            notBefore = "1970-01-01 00:00:00"
            notOnOrAfter = "2970-01-01 00:00:00"
            dayMonth = "0"
            dayMonthEnd = "31"
            month = "0"
            monthEnd = "12"
            hour = "0"
            hourEnd = "23"
            minute = "0"
            minuteEnd = "59"
        }
    }


}

class Certs {
    var keys: List<JwtSecretAlg> = listOf()
}

class JwtSecretAlg {
    var kid: String = ""
    var kty: String = ""
    var alg: String = ""
    var use: String = ""
    var n: String = ""
    var e: String = ""


}

@Path("/realms/${KEYCLOAK_REALM_NAME}/protocol/openid-connect/certs")
@RegisterRestClient(configKey = "auth")
interface KeycloakKeys {
    @GET
    fun certs(): Certs
}


/**
 * @author  yanfeiwuji
 * @date  2023/12/16 11:32
 */
class InitContext(
    val keycloak: Keycloak, val confService: ConfService,
    val keycloakKeys: KeycloakKeys,
    val objectMapper: ObjectMapper,
    val entityManager: EntityManager,
)

class Keys {
    var keys: List<String> = listOf()
}

@ApplicationScoped
class Init(
    val keycloak: Keycloak, val confService: ConfService, val objectMapper: ObjectMapper,
    val entityManager: EntityManager,
) {

    @Inject
    @RestClient
    lateinit var keycloakKeys: KeycloakKeys

    @field:ConfigProperty(name = "minio-client-secret")
    lateinit var minioSecret: String

    @Startup
    fun onStart() {
//        Uni.createFrom()
//            .item()
//            .emitOn(Infrastructure.getDefaultWorkerPool())
//            .subscribe()
//            .with(this::init, Throwable::printStackTrace)

        this.init(InitContext(keycloak, confService, keycloakKeys, objectMapper, entityManager))
    }


    @Transactional
    fun init(context: InitContext) {
        val keycloak = context.keycloak
        val hasRealm = initKcRealm(keycloak)
        if (hasRealm) {
            return
        }

        entityManager.createNativeQuery(
            """
                create or replace view auth.user as
                select u.username,
                       u.first_name,
                       u.last_name,
                       u.email,
                       u.email_verified,
                       u.created_timestamp,
                       u.enabled,
                       coalesce(jsonb_object_agg(ua.name, ua.value)
                                filter (where ua.name is not null and ua.value is not null),
                                '{}'\:\:jsonb
                       ) as user_attributes
                from keycloak.user_entity as u
                         left join keycloak.realm r on r.id = u.realm_id
                         left join keycloak.user_attribute ua on ua.user_id = u.id
                where r.name = '${KEYCLOAK_REALM_NAME}'
                group by u.id;
               
            """.trimIndent()
        ).executeUpdate()
        initKcClientScope(keycloak)
        initKcMinioClient(keycloak)
        initKcTokenExChange(keycloak)
        initPgrst(context)
    }

    fun initKcRealm(keycloak: Keycloak): Boolean {
        val hasRealm = keycloak.realms().findAll().any {
            it.realm == KEYCLOAK_REALM_NAME
        }
        if (hasRealm) {
            return hasRealm
        }
        keycloak.realms().create(KeycloakInit.LEAFOG_REALM)
        return false

    }

    fun initKcClientScope(keycloak: Keycloak) {
        val realm = keycloak.realm(KEYCLOAK_REALM_NAME)
        val clientScopeRepresentation = KeycloakInit.MINIO_CLIENT_SCOPE
        realm.clientScopes().create(clientScopeRepresentation)
        realm.clientScopes().findAll().first {
            it.name == KeycloakInit.MINIO_CLIENT_SCOPE.name
        }.let {
            realm.addDefaultDefaultClientScope(it.id)
        }
    }

    fun initKcMinioClient(keycloak: Keycloak) {
        val realm = keycloak.realm(KEYCLOAK_REALM_NAME)
        realm.clients().create(KeycloakInit.MINIO_CLIENT.also {
            it.secret = minioSecret
        })
    }

    fun initKcTokenExChange(keycloak: Keycloak) {
        val realm = keycloak.realm(KEYCLOAK_REALM_NAME)
        val clients = realm.clients()

        val clientList = clients.findAll()

        val minioClient = clientList.first { it.clientId == KeycloakInit.MINIO_CLIENT.clientId }
        val minioClientResource = clients.get(minioClient.id)

        minioClientResource.setPermissions(ManagementPermissionRepresentation(true))

        val realmManagementClient = clientList.first { it.clientId == "realm-management" }

        val realmManagementClientResource = clients.get(realmManagementClient.id)
        realmManagementClientResource.authorization().policies().time().create(KeycloakInit.ALL_TIME_CLIENT_POLICY)
        val allTimeId = realmManagementClientResource.authorization().policies().time()
            .findByName(KeycloakInit.ALL_TIME_CLIENT_POLICY.name).id

        val permissionsResource = realmManagementClientResource.authorization().permissions().resource()
        permissionsResource.findByName("token-exchange.permission.client.${minioClient.id}").let {
            it.policies = setOf(allTimeId)
            permissionsResource.findById(it.id).update(it)
        }

    }

    fun initPgrst(initContext: InitContext) {

        val jwtSecretAlg = initContext.keycloakKeys.certs().keys.first { it.alg == "RS256" }

        confService.updateAll(
            mapOf(
                PGRST_JWT_SECRET_KEY to initContext.objectMapper.writeValueAsString(jwtSecretAlg),
            )
        )
    }
}
