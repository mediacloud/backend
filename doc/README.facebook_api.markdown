# Facebook API

## Getting App ID and App Secret credentials

To get App ID and App Secret API authentication credentials:

1. Go to <https://developers.facebook.com/>
2. Click *Apps* -> *Add a New App*
3. Click *advanced setup* at the bottom
    1. Under *Display Name*, type in your app's name (e.g. `Media Cloud`)
    2. Under *Namespace*, type in your app's namespace (e.g. `mediacloud`)
    3. Under *Category*, choose a category that best suits your app (e.g. `Education`)
4. Click *Create App*
5. Click *Settings* on the left:
    1. In *Basic* tab, fill in your *Contact Email* and click *Save Changes*
    2. In *Advanced* tab, switch *Native or desktop app?* to `Yes` and click *Save Changes*
    3. In *Advanced* tab, switch *Social Discovery* to `No` and click *Save Changes*
6. From the *Settings* -> *Basic*, copy the *App ID*, *App Secret* and paste them into `mediawords.yml`

