# Photos on Unraid

Photos runs as four containers. Install them in this order from Community Applications (search **Photos**).

1. **Photos-Postgres**: set a database password (letters and numbers only). Keep the data folder on a cache or SSD share and back it up.
2. **Photos-Redis**: no changes needed.
3. **Photos-ML**: no changes needed. The first face scan downloads AI models and can take a while.
4. **Photos**:
   - **Database host** and **Redis host**: your Unraid server's IP address, for example `192.168.1.10`.
   - **Database password**: the same password you set in Photos-Postgres.
   - **Machine learning URL**: `http://YOUR-UNRAID-IP:3004`, using the same IP.
   - **Photo library**: the share where your photos should be stored.

Then open `http://YOUR-UNRAID-IP:2283` and create your admin account. The first account you create becomes the admin.

## Ports

| Container | Host port |
| --- | --- |
| Photos | 2283 |
| Photos-Postgres | 5433 |
| Photos-Redis | 6380 |
| Photos-ML | 3004 |

These avoid clashing with a stock Immich install. If you change a host port, change the matching value in the Photos container too.

## Updating

Click **Check for Updates** on the Docker tab, then **Apply Update** on the Photos container. Update Photos-ML only when this README says to, so it stays on a version the app supports.

## Android app

Download **photos-android-apk** from the latest **Photos build** run on the repository's Actions tab, install it, and use `http://YOUR-UNRAID-IP:2283` as the server address.

## Support

Open an issue at https://github.com/bdlnaredi/photos/issues.
