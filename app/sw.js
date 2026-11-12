/* The Dark Blue Book: offline support (0.3.20).
   Pages: network first, falling back to the saved copy offline, so a connected visitor always gets the latest version.
   Fonts, icons and d3: saved on install, served from the device.
   Photos and logos: saved as they're viewed (up to 300), refreshed in the background.
   Book data isn't handled here: the page saves its own copy of the public book (see saveSnap in index.html).
   Nothing signed-in or member-only is saved. */
const V='dbb-0.3.25',IMG='dbb-img',D3='https://cdnjs.cloudflare.com/ajax/libs/d3/7.9.0/d3.min.js';
const SHELL=['/','/privacy','/manifest.webmanifest','/fonts/fonts.css',"/fonts/ibm-plex-mono-latin-400-normal.woff2","/fonts/ibm-plex-mono-latin-500-normal.woff2","/fonts/ibm-plex-sans-latin-400-normal.woff2","/fonts/ibm-plex-sans-latin-500-normal.woff2","/fonts/ibm-plex-sans-latin-600-normal.woff2","/fonts/ibm-plex-sans-latin-ext-400-normal.woff2","/fonts/ibm-plex-sans-latin-ext-500-normal.woff2","/fonts/ibm-plex-sans-latin-ext-600-normal.woff2","/fonts/newsreader-latin-ext-opsz-normal.woff2","/fonts/newsreader-latin-opsz-normal.woff2",'/icons/icon-32.png','/icons/icon-180.png','/icons/icon-192.png','/icons/icon-512.png',D3];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>Promise.all(SHELL.map(u=>fetch(u,{cache:'reload',mode:u.startsWith('http')?'cors':'same-origin'}).then(r=>{if(r.ok&&!r.redirected)return c.put(u,r)}).catch(()=>{})))).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V&&k!==IMG&&k!=='dbb-data').map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
const timeout=(p,ms)=>Promise.race([p,new Promise((_,no)=>setTimeout(()=>no(new Error('timeout')),ms))]);
async function trim(c,max){const ks=await c.keys();for(let i=0;i<ks.length-max;i++)await c.delete(ks[i])}
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
  if(r.mode==='navigate'&&u.origin===location.origin){if(!/^\/(index\.html)?$|^\/privacy(\.html)?$/.test(u.pathname))return; /* /news and other server pages go straight to the network */
    const key=u.pathname.startsWith('/privacy')?'/privacy':'/';
    e.respondWith(timeout(fetch(r),6000).then(res=>{if(res.ok&&!res.redirected){const cp=res.clone();caches.open(V).then(c=>c.put(key,cp))}return res})
      .catch(()=>caches.match(key).then(m=>m||caches.match('/')).then(m=>m||new Response('Offline, and the book has not been saved on this device yet.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}}))));return}
  if((u.origin===location.origin&&/^\/(fonts|icons)\/|^\/manifest\.webmanifest$/.test(u.pathname))||r.url===D3){
    e.respondWith(caches.match(r.url===D3?D3:u.pathname).then(m=>m||fetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(V).then(c=>c.put(r.url===D3?D3:u.pathname,cp))}return res})));return}
  if(u.pathname.includes('/storage/v1/object/public/')){
    e.respondWith(caches.open(IMG).then(c=>c.match(r).then(m=>{const net=fetch(r).then(res=>{if(res.ok){c.put(r,res.clone()).then(()=>trim(c,300))}return res}).catch(()=>m);return m||net})));return}
});
