// Copies Leaflet + MarkerCluster into www/vendor so the app works without a CDN.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const out = path.join(root, 'www', 'vendor');

const files = [
  ['node_modules/leaflet/dist/leaflet.js', 'leaflet.js'],
  ['node_modules/leaflet/dist/leaflet.css', 'leaflet.css'],
  ['node_modules/leaflet.markercluster/dist/leaflet.markercluster.js', 'leaflet.markercluster.js'],
  ['node_modules/leaflet.markercluster/dist/MarkerCluster.css', 'MarkerCluster.css'],
  ['node_modules/leaflet.markercluster/dist/MarkerCluster.Default.css', 'MarkerCluster.Default.css']
];

fs.mkdirSync(out, { recursive: true });
for (const [src, dest] of files) {
  fs.copyFileSync(path.join(root, src), path.join(out, dest));
  console.log('copied', dest);
}

const imgSrc = path.join(root, 'node_modules/leaflet/dist/images');
const imgOut = path.join(out, 'images');
fs.mkdirSync(imgOut, { recursive: true });
for (const f of fs.readdirSync(imgSrc)) fs.copyFileSync(path.join(imgSrc, f), path.join(imgOut, f));
console.log('vendor ready');
