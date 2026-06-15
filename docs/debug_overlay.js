// Consola overlay para debug en mobile (iOS Safari no tiene devtools a mano).
// Captura console.log/warn/error + errores JS no atrapados. Godot print() en web
// va a console.log, así que también vemos el output del juego.
(function () {
  function init() {
    if (document.getElementById('dbgov')) return;
    var box = document.createElement('div');
    box.id = 'dbgov';
    box.style.cssText = 'position:fixed;left:0;right:0;bottom:0;max-height:42%;overflow-y:auto;z-index:99999;background:rgba(0,0,0,0.82);color:#9fe;font:11px/1.35 monospace;padding:4px 6px 30px;white-space:pre-wrap;word-break:break-word;-webkit-overflow-scrolling:touch;';
    var bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:100000;display:flex;gap:6px;padding:3px 6px;background:rgba(0,0,0,0.92);';

    function btn(t, fn) {
      var b = document.createElement('button');
      b.textContent = t;
      b.style.cssText = 'font:12px monospace;padding:3px 12px;background:#222;color:#fff;border:1px solid #555;border-radius:4px;';
      b.addEventListener('click', fn);
      b.addEventListener('touchstart', function (e) { e.stopPropagation(); });
      return b;
    }

    var hidden = false;
    bar.appendChild(btn('clear', function () { box.innerHTML = ''; }));
    bar.appendChild(btn('ocultar', function () {
      hidden = !hidden;
      box.style.display = hidden ? 'none' : 'block';
    }));
    document.body.appendChild(box);
    document.body.appendChild(bar);

    function add(kind, args) {
      var line = document.createElement('div');
      line.style.color = kind === 'err' ? '#ff6b6b' : (kind === 'warn' ? '#ffd166' : '#9fe');
      try {
        line.textContent = Array.prototype.map.call(args, function (a) {
          return (a && typeof a === 'object') ? JSON.stringify(a) : String(a);
        }).join(' ');
      } catch (e) { line.textContent = String(args); }
      box.appendChild(line);
      box.scrollTop = box.scrollHeight;
      while (box.childNodes.length > 400) box.removeChild(box.firstChild);
    }

    ['log', 'info', 'debug'].forEach(function (k) {
      var o = console[k] ? console[k].bind(console) : function () {};
      console[k] = function () { add('log', arguments); o.apply(console, arguments); };
    });
    var ow = console.warn ? console.warn.bind(console) : function () {};
    console.warn = function () { add('warn', arguments); ow.apply(console, arguments); };
    var oe = console.error ? console.error.bind(console) : function () {};
    console.error = function () { add('err', arguments); oe.apply(console, arguments); };

    window.addEventListener('error', function (e) {
      add('err', ['JS ERROR: ' + (e.message || e.error) + ' @' + (e.filename || '') + ':' + (e.lineno || '')]);
    });
    window.addEventListener('unhandledrejection', function (e) {
      var r = e.reason && (e.reason.stack || e.reason.message) || e.reason;
      add('err', ['PROMISE REJECT: ' + r]);
    });

    add('log', ['[overlay listo] ' + navigator.userAgent]);
  }

  if (document.body) init();
  else window.addEventListener('DOMContentLoaded', init);
})();
