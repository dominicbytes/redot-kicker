#define _GNU_SOURCE
#include <libsecret/secret.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *HEADER = "RKCH/1";
static const gsize MAX_TARGET_BYTES = 512;
static const gsize MAX_SECRET_BYTES = 4096;

static const SecretSchema REDOT_KICKER_SCHEMA = {
    .name = "org.redotengine.redot_kicker",
    .flags = SECRET_SCHEMA_NONE,
    .attributes = {
        {"target", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {NULL, 0},
    },
};

static void strip_newline(char *value) {
    size_t length = strlen(value);
    if (length > 0 && value[length - 1] == '\n') value[--length] = '\0';
    if (length > 0 && value[length - 1] == '\r') value[length - 1] = '\0';
}

static void respond(const char *status, const char *payload, const char *detail) {
    printf("%s\n%s\n%s\n%s\n", HEADER, status, payload ? payload : "", detail ? detail : "");
    fflush(stdout);
}

static void respond_error(const GError *error) {
    if (error && error->domain == SECRET_ERROR && error->code == SECRET_ERROR_IS_LOCKED)
        respond("LOCKED", "", "secret collection is locked");
    else if (error && error->domain == G_IO_ERROR && error->code == G_IO_ERROR_CANCELLED)
        respond("DENIED", "", "secret service operation cancelled");
    else
        respond("UNAVAILABLE", "", "secret service operation failed");
}

int main(void) {
    char *lines[4] = {NULL, NULL, NULL, NULL};
    size_t capacities[4] = {0, 0, 0, 0};
    for (int index = 0; index < 4; ++index) {
        if (getline(&lines[index], &capacities[index], stdin) < 0) {
            respond("PROTOCOL_ERROR", "", "incomplete request");
            for (int cleanup = 0; cleanup < 4; ++cleanup) free(lines[cleanup]);
            return 2;
        }
        strip_newline(lines[index]);
    }
    if (strcmp(lines[0], HEADER) != 0) {
        respond("PROTOCOL_ERROR", "", "unsupported protocol");
        goto protocol_error;
    }
    if (strcmp(lines[1], "ping") == 0) {
        GError *error = NULL;
        SecretService *service = secret_service_get_sync(SECRET_SERVICE_NONE, NULL, &error);
        if (!service) {
            respond_error(error);
            g_clear_error(&error);
            goto operation_error;
        }
        g_object_unref(service);
        respond("OK", "", "linux-secret-service");
        goto success;
    }

    gsize target_size = 0;
    gsize secret_size = 0;
    guchar *target_bytes = g_base64_decode(lines[2], &target_size);
    guchar *secret_bytes = g_base64_decode(lines[3], &secret_size);
    if (!target_bytes || !secret_bytes || target_size == 0 || target_size > MAX_TARGET_BYTES ||
        secret_size > MAX_SECRET_BYTES || !g_utf8_validate((const gchar *)target_bytes, target_size, NULL)) {
        respond("PROTOCOL_ERROR", "", "invalid field encoding or size");
        if (target_bytes) g_free(target_bytes);
        if (secret_bytes) {
            memset(secret_bytes, 0, secret_size);
            g_free(secret_bytes);
        }
        goto protocol_error;
    }
    gchar *target = g_strndup((const gchar *)target_bytes, target_size);
    gchar *secret = g_strndup((const gchar *)secret_bytes, secret_size);
    g_free(target_bytes);
    memset(secret_bytes, 0, secret_size);
    g_free(secret_bytes);
    GError *error = NULL;

    if (strcmp(lines[1], "store") == 0) {
        if (secret_size == 0 || !secret_password_store_sync(&REDOT_KICKER_SCHEMA, SECRET_COLLECTION_DEFAULT,
                "Redot Kicker broker session", secret, NULL, &error, "target", target, NULL)) {
            if (secret_size == 0) respond("PROTOCOL_ERROR", "", "broker session is empty");
            else respond_error(error);
            g_clear_error(&error);
            memset(secret, 0, strlen(secret));
            g_free(secret);
            g_free(target);
            goto operation_error;
        }
        memset(secret, 0, strlen(secret));
        g_free(secret);
        g_free(target);
        respond("OK", "", "stored");
        goto success;
    }

    if (strcmp(lines[1], "read") == 0) {
        gchar *stored = secret_password_lookup_sync(&REDOT_KICKER_SCHEMA, NULL, &error, "target", target, NULL);
        memset(secret, 0, strlen(secret));
        g_free(secret);
        g_free(target);
        if (!stored) {
            if (error) {
                respond_error(error);
                g_clear_error(&error);
                goto operation_error;
            }
            respond("NOT_FOUND", "", "credential not found");
            goto success;
        }
        const gsize stored_size = strlen(stored);
        if (stored_size > MAX_SECRET_BYTES) {
            secret_password_free(stored);
            respond("PROTOCOL_ERROR", "", "stored broker session exceeds protocol limit");
            goto protocol_error;
        }
        gchar *encoded = g_base64_encode((const guchar *)stored, stored_size);
        secret_password_free(stored);
        respond("OK", encoded, "read");
        g_free(encoded);
        goto success;
    }

    if (strcmp(lines[1], "delete") == 0) {
        const gboolean cleared = secret_password_clear_sync(&REDOT_KICKER_SCHEMA, NULL, &error, "target", target, NULL);
        memset(secret, 0, strlen(secret));
        g_free(secret);
        g_free(target);
        if (!cleared && error) {
            respond_error(error);
            g_clear_error(&error);
            goto operation_error;
        }
        respond(cleared ? "OK" : "NOT_FOUND", "", cleared ? "deleted" : "credential not found");
        goto success;
    }

    memset(secret, 0, strlen(secret));
    g_free(secret);
    g_free(target);
    respond("PROTOCOL_ERROR", "", "unknown command");

protocol_error:
    for (int index = 0; index < 4; ++index) free(lines[index]);
    return 2;
operation_error:
    for (int index = 0; index < 4; ++index) free(lines[index]);
    return 1;
success:
    for (int index = 0; index < 4; ++index) free(lines[index]);
    return 0;
}
