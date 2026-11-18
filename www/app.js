/* Crime Near Me — iPhone (Capacitor) version
 * Crime data: data.police.uk · Postcodes: postcodes.io
 */
(function () {
  'use strict';

  // ---------- Crime types ----------
  const TYPES = {
    'violent-crime':         { name: 'Violence & sexual offences', colour: '#e5484d' },
    'robbery':               { name: 'Robbery',                    colour: '#ff7b2e' },
    'possession-of-weapons': { name: 'Possession of weapons',      colour: '#c2185b' },
    'burglary':              { name: 'Burglary',                   colour: '#f5a524' },
    'vehicle-crime':         { name: 'Vehicle crime',              colour: '#3e9bff' },
    'theft-from-the-person': { name: 'Theft from the person',      colour: '#a26bff' },
    'other-theft':           { name: 'Other theft',                colour: '#7c8cff' },
    'shoplifting':           { name: 'Shoplifting',                colour: '#2fb7a5' },
    'bicycle-theft':         { name: 'Bicycle theft',              colour: '#5ec26a' },
    'criminal-damage-arson': { name: 'Criminal damage & arson',    colour: '#ff5c8a' },
    'public-order':          { name: 'Public order',               colour: '#e6d34a' },
    'anti-social-behaviour': { name: 'Anti-social behaviour',      colour: '#8a94a3' },
    'drugs':                 { name: 'Drugs',                      colour: '#9be15d' },
    'other-crime':           { name: 'Other crime',                colour: '#b0a18f' }
  };
  const GROUPS = [
    ['Violence & weapons', ['violent-crime', 'robbery', 'possession-of-weapons']],
    ['Theft',              ['burglary', 'vehicle-crime', 'theft-from-the-person', 'other-theft', 'shoplifting', 'bicycle-theft']],
    ['Damage & disorder',  ['criminal-damage-arson', 'public-order', 'anti-social-behaviour']],
    ['Drugs & other',      ['drugs', 'other-crime']]
  ];

  // ---------- Storage (safe) ----------
  const store = {
    get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* ignore */ } }
  };

  const state = {
    crimes: [],
    hidden: new Set(store.get('hidden', [])),
    centre: null,
    place: ''
  };

  // ---------- Helpers ----------
  const $ = id => document.getElementById(id);
  const esc = s => String(s || '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const colour = c => (TYPES[c] ? TYPES[c].colour : '#cccccc');
  const typeName = c => (TYPES[c] ? TYPES[c].name : c.replace(/-/g, ' '));
  const monthLabel = m => { const [y, mo] = m.split('-'); return new Date(y, mo - 1).toLocaleString('en-GB', { month: 'long', year: 'numeric' }); };
  const saveHidden = () => store.set('hidden', [...state.hidden]);

  function toast(msg) {
    const t = $('toast'); t.textContent = msg; t.style.display = 'block';
    clearTimeout(toast.t); toast.t = setTimeout(() => (t.style.display = 'none'), 4000);
  }

  async function getJson(url) {
    let res;
    try { res = await fetch(url); }
    catch (e) { throw new Error('No connection. Check your signal and try again.'); }
    if (res.status === 503) throw new Error('Too many crimes here to load at once. Tap a more specific spot.');
    if (res.status === 404) throw new Error('Not found');
    if (!res.ok) throw new Error('Police data error (' + res.status + '). Try again shortly.');
    return res.json();
  }

  // ---------- Data ----------
  async function getMonths() {
    const cached = store.get('months', null);
    if (cached && Date.now() - cached.t < 6 * 3600e3) return cached.v;
    const data = await getJson('https://data.police.uk/api/crimes-street-dates');
    const months = data.map(d => d.date).sort().reverse().slice(0, 24);
    store.set('months', { t: Date.now(), v: months });
    return months;
  }

  async function getCrimes(lat, lng, month) {
    const url = 'https://data.police.uk/api/crimes-street/all-crime?lat=' + lat.toFixed(4) +
      '&lng=' + lng.toFixed(4) + (month ? '&date=' + month : '');
    const data = await getJson(url);
    return data.map(c => ({
      c: c.category,
      la: Number(c.location.latitude),
      ln: Number(c.location.longitude),
      s: c.location.street ? c.location.street.name : '',
      o: c.outcome_status ? c.outcome_status.category : '',
      m: c.month
    }));
  }

  async function lookupPostcode(pc) {
    const clean = pc.replace(/\s+/g, '').toUpperCase();
    let res;
    try { res = await fetch('https://api.postcodes.io/postcodes/' + encodeURIComponent(clean)); }
    catch (e) { throw new Error('No connection. Check your signal and try again.'); }
    if (!res.ok) throw new Error('Postcode not found');
    const r = (await res.json()).result;
    if (r.latitude == null) throw new Error('No location for that postcode');
    return { lat: r.latitude, lng: r.longitude, label: r.postcode };
  }

  // ---------- Map ----------
  const map = L.map('map', { zoomControl: false }).setView([53.32, -3.83], 13);
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap &copy; CARTO · data.police.uk'
  }).addTo(map);

  const cluster = L.markerClusterGroup({ maxClusterRadius: 40, spiderfyOnMaxZoom: true, showCoverageOnHover: false });
  map.addLayer(cluster);
  let areaCircle = null;

  const iconCache = {};
  const icon = c => iconCache[c] || (iconCache[c] = L.divIcon({
    className: '', iconSize: [14, 14], html: '<div class="pin" style="background:' + colour(c) + '"></div>'
  }));

  // ---------- Rendering ----------
  function counts() {
    const n = {};
    state.crimes.forEach(c => (n[c.c] = (n[c.c] || 0) + 1));
    return n;
  }

  function render() {
    cluster.clearLayers();
    const markers = [];
    state.crimes.forEach(cr => {
      if (state.hidden.has(cr.c)) return;
      const m = L.marker([cr.la, cr.ln], { icon: icon(cr.c) });
      m.bindPopup(
        '<div class="pop-cat" style="color:' + colour(cr.c) + '">' + esc(typeName(cr.c)) + '</div>' +
        '<div>' + esc(cr.s) + '</div>' +
        '<div class="pop-sub">' + esc(monthLabel(cr.m)) + (cr.o ? ' · ' + esc(cr.o) : '') + '</div>');
      markers.push(m);
    });
    cluster.addLayers(markers);

    const total = state.crimes.length, shown = markers.length;
    $('status').innerHTML = state.place
      ? '<b>' + shown + '</b>' + (shown !== total ? ' of ' + total : '') + ' crimes · ' + esc(state.place)
      : 'Search a postcode, tap 📍, or tap the map';

    const allTypes = Object.keys(TYPES);
    const on = allTypes.filter(k => !state.hidden.has(k)).length;
    $('filterCount').textContent = on === allTypes.length ? '' : '(' + on + ')';

    renderChips();
  }

  function renderChips() {
    const n = counts();
    const keys = Object.keys(n).sort((a, b) => n[b] - n[a]);
    $('chips').innerHTML = keys.map(k =>
      '<div class="chip' + (state.hidden.has(k) ? ' off' : '') + '" data-k="' + k + '">' +
      '<span class="dot" style="background:' + colour(k) + '"></span>' + esc(typeName(k)) +
      ' <span class="n">' + n[k] + '</span></div>').join('');
  }

  function renderFilterList() {
    const n = counts();
    $('filterList').innerHTML = GROUPS.map(([title, keys]) =>
      '<div class="group"><span>' + title + '</span><button data-group="' + keys.join(',') + '">toggle</button></div>' +
      keys.map(k =>
        '<div class="item' + (state.hidden.has(k) ? '' : ' on') + (n[k] ? '' : ' empty') + '" data-k="' + k + '">' +
        '<span class="dot" style="background:' + colour(k) + '"></span>' +
        '<span class="name">' + esc(typeName(k)) + '</span>' +
        (state.place ? '<span class="n">' + (n[k] || 0) + '</span>' : '') +
        '<span class="switch"></span></div>').join('')
    ).join('');
  }

  // ---------- Filter interactions ----------
  function toggle(k) { state.hidden.has(k) ? state.hidden.delete(k) : state.hidden.add(k); saveHidden(); }

  $('chips').addEventListener('click', e => {
    const chip = e.target.closest('.chip'); if (!chip) return;
    toggle(chip.dataset.k); render();
  });

  $('filterBtn').onclick = () => { renderFilterList(); $('overlay').classList.add('open'); };
  $('doneBtn').onclick = () => { $('overlay').classList.remove('open'); render(); };
  $('overlay').addEventListener('click', e => { if (e.target.id === 'overlay') $('doneBtn').onclick(); });

  $('filterList').addEventListener('click', e => {
    const g = e.target.closest('[data-group]');
    if (g) {
      const keys = g.dataset.group.split(',');
      const allOn = keys.every(k => !state.hidden.has(k));
      keys.forEach(k => (allOn ? state.hidden.add(k) : state.hidden.delete(k)));
      saveHidden(); renderFilterList(); return;
    }
    const item = e.target.closest('.item');
    if (item) { toggle(item.dataset.k); renderFilterList(); }
  });

  $('allBtn').onclick = () => { state.hidden.clear(); saveHidden(); renderFilterList(); };
  $('noneBtn').onclick = () => { Object.keys(TYPES).forEach(k => state.hidden.add(k)); saveHidden(); renderFilterList(); };

  // ---------- Loading ----------
  async function load(lat, lng, place) {
    state.centre = [lat, lng];
    $('hint').style.display = 'none';
    $('status').textContent = 'Loading crimes…';
    if (areaCircle) map.removeLayer(areaCircle);
    areaCircle = L.circle([lat, lng], { radius: 1609, color: '#e5484d', weight: 1, fillOpacity: 0.04, interactive: false }).addTo(map);
    map.flyTo([lat, lng], 14, { duration: 0.6 });
    try {
      state.crimes = await getCrimes(lat, lng, $('month').value);
      state.place = place;
      if (!state.crimes.length) toast('No crimes recorded here for that month (or not published yet).');
    } catch (err) {
      state.crimes = []; state.place = ''; toast(err.message);
    }
    render();
  }

  async function searchPostcode() {
    const pc = $('pc').value.trim(); if (!pc) return;
    $('pc').blur();
    try { const r = await lookupPostcode(pc); load(r.lat, r.lng, r.label); }
    catch (err) { toast(err.message); }
  }
  $('goBtn').onclick = searchPostcode;
  $('pc').addEventListener('keydown', e => { if (e.key === 'Enter') searchPostcode(); });

  async function locate() {
    const Geo = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Geolocation;
    try {
      let lat, lng;
      if (Geo) {
        const p = await Geo.getCurrentPosition({ enableHighAccuracy: true, timeout: 10000 });
        lat = p.coords.latitude; lng = p.coords.longitude;
      } else {
        const p = await new Promise((res, rej) =>
          navigator.geolocation.getCurrentPosition(res, rej, { enableHighAccuracy: true, timeout: 10000 }));
        lat = p.coords.latitude; lng = p.coords.longitude;
      }
      load(lat, lng, 'Your location');
    } catch (e) {
      toast('Couldn’t get your location. Check Settings › Privacy › Location, or use a postcode.');
    }
  }
  $('locBtn').onclick = locate;

  map.on('click', e => load(e.latlng.lat, e.latlng.lng, 'Map point'));
  $('month').onchange = () => { if (state.centre) load(state.centre[0], state.centre[1], state.place || 'Map point'); };

  // ---------- Start ----------
  (async function init() {
    render();
    try {
      const months = await getMonths();
      $('month').innerHTML = months.map(m => '<option value="' + m + '">' + monthLabel(m) + '</option>').join('');
    } catch (err) {
      toast('Couldn’t reach police data: ' + err.message);
    }
  })();
})();
