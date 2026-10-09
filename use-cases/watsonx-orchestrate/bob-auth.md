# Bob Shell Authentication for WXA

`bob-auth.sh` authenticates IBM Bob Shell by reading `.env`, writing the expected `~/.bob/token.json` and `~/.bob/config.json` files, and validating Bob CLI access with `bob --list-sessions --accept-license true`.

Required `.env` values:

```bash
BOB_API_KEY="..."
BOB_ENDPOINT="https://api.us-east.bob.ibm.com"
BOB_AUTH_ENDPOINT="https://console-ibm-prod.verify.ibm.com"
BOB_REGION="us-east"
```

Do not commit real `.env` values or credential files.
