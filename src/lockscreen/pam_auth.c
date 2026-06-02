#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <security/pam_appl.h>
#include "pam_auth.h"

static char *pam_password = NULL;

static int
pam_conv_func(int num_msg, const struct pam_message **msg,
              struct pam_response **resp, void *app_data)
{
    if (num_msg <= 0)
        return PAM_CONV_ERR;

    struct pam_response *reply = calloc(num_msg, sizeof(struct pam_response));
    if (!reply)
        return PAM_BUF_ERR;

    for (int i = 0; i < num_msg; i++) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF) {
            reply[i].resp = pam_password ? strdup(pam_password) : strdup("");
            reply[i].resp_retcode = 0;
        }
    }

    *resp = reply;
    return PAM_SUCCESS;
}

int
singularity_pam_authenticate(const char *username, const char *password)
{
    pam_password = (char *)password;

    struct pam_conv conv = {
        .conv = pam_conv_func,
        .appdata_ptr = NULL
    };

    pam_handle_t *pamh = NULL;
    int ret = pam_start("singularity-lockscreen", username, &conv, &pamh);
    if (ret != PAM_SUCCESS) {
        pam_password = NULL;
        return ret;
    }

    ret = pam_authenticate(pamh, 0);
    pam_end(pamh, ret);

    pam_password = NULL;
    return ret;
}