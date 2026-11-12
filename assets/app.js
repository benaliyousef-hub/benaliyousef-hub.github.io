(function () {
  'use strict';
  var KEY = 'vm-precio';
  function fmt(n, d) { return n.toLocaleString('es-ES', { minimumFractionDigits: d, maximumFractionDigits: d }); }
  function eur(v) {
    if (!isFinite(v)) return '-';
    var d = v >= 20 ? 0 : (v > 0 && v < 0.0095) ? 4 : (v > 0 && v < 0.095) ? 3 : 2;
    return fmt(v, d) + ' €';
  }
  function kwh(v) {
    if (!isFinite(v)) return '-';
    var d = v >= 100 ? 0 : v >= 10 ? 1 : (v > 0 && v < 0.1) ? 3 : 2;
    return fmt(v, d) + ' kWh';
  }
  function saved() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function save(v) { try { localStorage.setItem(KEY, v); } catch (e) { /* storage unavailable */ } }

  function initCalc(form) {
    var f = form.elements;
    function val(name) { var v = parseFloat(String(f[name].value).replace(',', '.')); return isFinite(v) && v >= 0 ? v : 0; }
    function out(key, text) { var el = form.querySelector('[data-out="' + key + '"]'); if (el) el.textContent = text; }
    function update() {
      var ciclo = form.getAttribute('data-modo') === 'ciclo';
      var precio = val('precio'), dias = Math.min(val('dias'), 366);
      var kd, unit;
      if (ciclo) { kd = val('kwh') * val('usos') / 7; unit = val('kwh') * precio; }
      else {
        var carga = Math.min(val('factor'), 100) / 100;
        kd = val('w') * carga * Math.min(val('horas'), 24) / 1000;
        unit = val('w') * carga / 1000 * precio;
      }
      out('unitLabel', ciclo ? 'Por uso' : 'Por hora');
      out('unit', eur(unit));
      out('dia', eur(kd * precio)); out('kwhDia', kwh(kd));
      out('mes', eur(kd * 30 * precio)); out('kwhMes', kwh(kd * 30));
      out('ano', eur(kd * dias * precio)); out('kwhAno', kwh(kd * dias));
    }
    var s = saved();
    if (s && isFinite(parseFloat(s))) f.precio.value = s;
    form.addEventListener('input', function (e) {
      if (e.target === f.precio && val('precio') > 0) save(String(val('precio')));
      update();
    });

    var select = form.querySelector('#aparato-select');
    var dataEl = document.getElementById('aparatos-data');
    if (select && dataEl) {
      var list = [];
      try { list = JSON.parse(dataEl.textContent); } catch (e) { list = []; }
      list.forEach(function (a) {
        var o = document.createElement('option'); o.value = a.s; o.textContent = a.n; select.appendChild(o);
      });
      select.value = select.getAttribute('data-initial') || (list[0] && list[0].s);
      select.addEventListener('change', function () {
        var a = list.filter(function (x) { return x.s === select.value; })[0];
        if (!a) return;
        form.setAttribute('data-modo', a.m);
        if (a.m === 'ciclo') { f.kwh.value = a.kwh; f.usos.value = a.usos; }
        else { f.w.value = a.w; f.horas.value = a.horas; f.factor.value = a.factor; }
        f.dias.value = a.dias;
        update();
      });
    }
    update();
  }
  Array.prototype.forEach.call(document.querySelectorAll('form.calc'), initCalc);

  var filtro = document.getElementById('filtro');
  if (filtro) {
    var norm = function (s) { return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); };
    filtro.addEventListener('input', function () {
      var q = norm(filtro.value.trim());
      Array.prototype.forEach.call(document.querySelectorAll('.cat-block'), function (block) {
        var any = false;
        Array.prototype.forEach.call(block.querySelectorAll('.card'), function (c) {
          var hit = !q || norm(c.getAttribute('data-name') || '').indexOf(q) !== -1;
          c.hidden = !hit; if (hit) any = true;
        });
        block.hidden = !any;
      });
    });
  }
})();
