# Self-hosted road routing (free forever)

eRefill draws rider routes and ETAs with [OSRM](https://project-osrm.org),
open-source routing software that uses OpenStreetMap roads. By default the
app uses the FOSSGIS community server (`routing.openstreetmap.de`), with the
OSRM demo server as a last resort. Both are shared public servers meant for
light use.

To remove that dependency, run OSRM yourself. It is free and open source, and
the Philippines map fits on a small machine (about 4 GB of RAM to prepare the
map, about 1 GB to serve it).

## 1. Prepare the map (one time, then monthly to pick up new roads)

You need Docker installed.

```bash
mkdir osrm && cd osrm
curl -LO https://download.geofabrik.de/asia/philippines-latest.osm.pbf

docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/philippines-latest.osm.pbf
docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-partition /data/philippines-latest.osrm
docker run -t -v "${PWD}:/data" ghcr.io/project-osrm/osrm-backend \
  osrm-customize /data/philippines-latest.osrm
```

## 2. Run the server

```bash
docker run -d --restart unless-stopped -p 5000:5000 -v "${PWD}:/data" \
  ghcr.io/project-osrm/osrm-backend \
  osrm-routed --algorithm mld /data/philippines-latest.osrm
```

Test it with a route in Cantilan:

```bash
curl "http://localhost:5000/route/v1/driving/125.97,9.33;125.98,9.34?overview=false"
```

The answer should start with `{"code":"Ok"`.

Put the server behind HTTPS before using it from phones. A reverse proxy such
as Caddy or nginx with a free Let's Encrypt certificate works.

## 3. Point the app at it

Build the app with your server's address:

```bash
flutter build apk --release --dart-define=ROUTING_URL=https://routing.example.com
```

The app tries your server first. If it is down, the app falls back to the
public servers, and then to a straight line, so deliveries keep working.

## Map tiles

Maps use Esri satellite imagery (with Esri road and label overlays) and
OpenStreetMap street tiles. Each map shows the credit line those services
require. There is no high-resolution satellite imagery that is both open
source and free with no limits. The fully open option is the OpenStreetMap
street style (`AppMapStyle.streets`), which can also be self-hosted, for
example with [OpenMapTiles](https://openmaptiles.org).
