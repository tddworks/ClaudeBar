/// The report's own script: it shows what `RecapReportPage` already says —
/// another unit, the bars stacked by a split, one day's figures, a list in
/// another order — and nothing else. It counts no usage and formats no
/// number, asks the network for nothing, and writes every name as text, never
/// as markup. When it cannot run, the page's own markup stays.
enum RecapReportScript {
    static let source = #"""
    (function () {
      var data = JSON.parse(document.getElementById('recap-data').textContent);
      var live = document.getElementById('live');
      var tip = document.getElementById('tip');
      var state = { unit: data.unit, by: 'total', day: null, sort: {}, open: {} };
      var SHOWN = 8;

      function el(tag, cls, text) {
        var node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text != null) node.textContent = text;
        return node;
      }
      function add(parent) {
        for (var i = 1; i < arguments.length; i++) if (arguments[i]) parent.appendChild(arguments[i]);
        return parent;
      }
      function button(cls, text, act) {
        var b = el('button', cls, text);
        b.type = 'button';
        b.onclick = act;
        return b;
      }
      function card(title, aside) {
        return add(el('section'), add(el('h2'), el('span', null, title), aside));
      }
      function choice(options, current, pick) {
        var group = el('div', 'seg');
        options.forEach(function (option) {
          var b = button(option.id === current ? 'on' : null, option.name, function () { pick(option.id); });
          b.setAttribute('aria-pressed', option.id === current);
          group.appendChild(b);
        });
        return group;
      }
      function changed(change) {
        return change ? el('span', 'chg ' + (change.up ? 'up' : 'down'), change.text) : null;
      }
      function facts(list, cls) {
        var box = el('div', cls);
        list.forEach(function (fact) {
          add(box, add(el('div', 'tile'), el('div', 'k', fact.k), el('div', 'v', fact.v)));
        });
        return box;
      }
      function splitAt(view, id) {
        for (var i = 0; i < view.splits.length; i++) if (view.splits[i].id === id) return i;
        return -1;
      }

      // The total, its unit and its change.
      function lead(view) {
        var units = data.units.length > 1
          ? choice(data.units, state.unit, function (id) { state.unit = id; render(); }) : null;
        var section = card('The ' + data.period, units);
        var line = add(el('div', 'lead'), el('span', 'total', view.total), el('span', 'cap', view.caption));
        if (view.change) {
          add(line, add(el('span', 'change'),
            el('b', view.change.up ? 'up' : 'down', (view.change.up ? '▲ ' : '▼ ') + view.change.text),
            el('span', null, data.compared)));
        }
        add(section, line);
        if (view.subline.length) add(section, el('div', 'subline', view.subline.join('  ·  ')));
        return section;
      }

      // A bar a day, whole or stacked by a split; a day can be picked.
      function chart(view) {
        var options = [{ id: 'total', name: 'Total' }].concat(view.splits.map(function (split) {
          return { id: split.id, name: split.by };
        }));
        var section = card('Day by day', choice(options, state.by, function (id) { state.by = id; render(); }));
        var at = splitAt(view, state.by);
        var quiet = view.days.length > 10;
        var bars = el('div', 'chart' + (quiet ? ' month' : '') + (state.day != null ? ' dim' : ''));
        view.days.forEach(function (day, index) {
          var own = data.days[index];
          var picked = state.day === index;
          var column = button('day' + (day.peak ? ' peak' : '') + (picked ? ' sel' : ''), null, function () {
            state.day = picked ? null : index;
            hide();
            render();
          });
          column.setAttribute('aria-label', own.title + ': ' + day.value);
          column.setAttribute('aria-pressed', picked);
          var bar = el('div', 'bar');
          bar.style.height = (day.share > 0 ? Math.max(day.share * 100, 2) : 0) + '%';
          if (at >= 0) {
            bar.className = 'bar stacked';
            day.parts[at].forEach(function (part) {
              var piece = el('i', view.splits[at].rows[part.row].hue);
              piece.style.height = (part.share * 100) + '%';
              bar.appendChild(piece);
            });
          }
          var shown = day.share > 0 && (!quiet || day.peak || picked);
          add(column, add(el('div', 'plot'), shown ? el('span', 'v', day.value) : null, bar), el('span', 'l', own.label));
          column.onmouseenter = column.onfocus = function () { show(column, view, index); };
          column.onmouseleave = column.onblur = hide;
          bars.appendChild(column);
        });
        add(section, bars);
        if (state.day == null) {
          add(section, el('div', 'hint', 'Point at a day for its figures; click one to read the lists for that day alone.'));
        }
        return section;
      }

      // A row a day, a cell an hour; pointing at one says it in every unit.
      function hours(view) {
        if (!view.hours) return null;
        var section = card('Hour by hour', null);
        add(section, el('div', 'peak', 'Busiest hour: ' + view.hours.peak));
        var grid = el('div', 'heat live' + (view.days.length > 10 ? ' month' : ''));
        var axis = add(el('div', 'hr axis'), el('span', 'hl'));
        for (var mark = 0; mark < 24; mark += 3) add(axis, el('span', 'ha', (mark < 10 ? '0' : '') + mark));
        add(grid, axis);
        function row(cls, label, cells, index) {
          var line = add(el('div', cls), el('span', 'hl', label));
          var held = {};
          cells.forEach(function (cell) { held[cell.h] = cell; });
          for (var h = 0; h < 24; h++) {
            var box = el('i', held[h] ? 'h' + held[h].level : null);
            box.dataset.h = h;
            if (index != null) box.dataset.d = index;
            line.appendChild(box);
          }
          return line;
        }
        add(grid, row('hr all', 'All', view.hours.ofDay, null));
        view.hours.rows.forEach(function (day, index) {
          var cls = 'hr' + (state.day === index ? ' sel' : '');
          var line = day.known ? row(cls, data.days[index].label, day.cells, index)
            : add(el('div', cls), el('span', 'hl', data.days[index].label), el('span', 'nk', 'no hours kept for this day'));
          line.dataset.d = index;
          grid.appendChild(line);
        });
        grid.onmouseover = function (event) {
          var h = event.target.dataset.h;
          if (h == null) return hide();
          hour(event.target, +h, event.target.dataset.d == null ? null : +event.target.dataset.d);
        };
        grid.onmouseleave = hide;
        grid.onclick = function (event) {
          var line = event.target.closest('.hr');
          if (!line || line.dataset.d == null) return;
          state.day = state.day === +line.dataset.d ? null : +line.dataset.d;
          hide();
          render();
        };
        var legend = add(el('div', 'legend'), el('span', null, 'Less'));
        for (var level = 0; level <= 4; level++) add(legend, el('i', level ? 'h' + level : null));
        return add(section, grid, add(legend, el('span', null, 'More')));
      }

      // One hour's figures beside its cell, in every unit the page offers.
      function hour(anchor, h, index) {
        tip.textContent = '';
        var next = (h + 1) % 24;
        var span = (h < 10 ? '0' : '') + h + ':00\u2013' + (next < 10 ? '0' : '') + next + ':00';
        add(tip, el('b', null, index == null ? 'Every day \u00B7 ' + span : data.days[index].title + ' \u00B7 ' + span));
        var any = false;
        data.units.forEach(function (unit) {
          var all = data.views[unit.id].hours;
          var cells = !all ? [] : index == null ? all.ofDay : all.rows[index].cells;
          cells.forEach(function (cell) {
            if (cell.h !== h) return;
            any = true;
            add(tip, add(el('div', 'f'), el('span', null, unit.name), el('span', null, cell.value)));
          });
        });
        if (!any) add(tip, el('div', 'f', 'Nothing in this hour.'));
        place(anchor);
      }

      // The picked day's own figures.
      function picked(view) {
        if (state.day == null) return null;
        var own = data.days[state.day];
        var section = card(own.title, button('link', 'Show the whole ' + data.period, function () {
          state.day = null;
          render();
        }));
        add(section, add(el('div', 'lead'), el('span', 'total small', view.days[state.day].value),
          el('span', 'cap', view.caption)));
        if (own.facts.length) add(section, facts(own.facts, 'tiles facts'));
        return section;
      }

      // A split's rows: the range's, or what the picked day held, largest first.
      function rows(view, at) {
        var split = view.splits[at];
        var list = state.day == null ? split.rows : view.days[state.day].parts[at].map(function (part) {
          var row = split.rows[part.row];
          return { name: row.name, hue: row.hue, value: part.value, amount: part.amount, share: part.share,
                   shareText: part.shareText, change: null };
        }).sort(function (a, b) { return b.amount - a.amount; });
        var order = state.sort[split.id];
        if (!order) return list;
        var sign = order.down ? -1 : 1;
        return list.slice().sort(function (a, b) {
          if (order.key === 'name') return sign * a.name.localeCompare(b.name);
          var x = order.key === 'change' ? (a.change ? a.change.amount : -Infinity) : a.amount;
          var y = order.key === 'change' ? (b.change ? b.change.amount : -Infinity) : b.amount;
          return sign * (x - y);
        });
      }

      function split(view, at) {
        var which = view.splits[at];
        var list = rows(view, at);
        var title = state.day == null ? which.title : which.title + ' · ' + data.days[state.day].title;
        var section = card(title, null);

        var stack = el('div', 'stack');
        list.forEach(function (row) {
          if (row.share <= 0) return;
          var piece = el('div', row.hue);
          piece.style.width = (row.share * 100) + '%';
          piece.title = row.name + ' · ' + row.shareText;
          stack.appendChild(piece);
        });
        add(section, stack);
        if (!list.length) add(section, el('div', 'hint', 'Nothing that day.'));

        var keys = [{ key: 'name', name: 'Name' }, { key: 'amount', name: 'Value' }];
        if (list.some(function (row) { return row.change; })) keys.push({ key: 'change', name: 'Change' });
        var order = state.sort[which.id];
        var sorter = add(el('div', 'sort'), el('span', null, 'Sort'));
        keys.forEach(function (option) {
          var on = order && order.key === option.key;
          var mark = on ? (order.down ? ' ↓' : ' ↑') : '';
          add(sorter, button(on ? 'on' : null, option.name + mark, function () {
            state.sort[which.id] = { key: option.key, down: on ? !order.down : option.key !== 'name' };
            render();
          }));
        });
        if (list.length > 1) add(section, sorter);

        var open = state.open[which.id] || list.length <= SHOWN;
        var body = el('div', 'rows');
        (open ? list : list.slice(0, SHOWN)).forEach(function (row) {
          add(body, add(el('div', 'row'),
            el('span', 'dot ' + row.hue), el('span', 'name', row.name), el('span', 'val', row.value),
            el('span', 'share', row.shareText), changed(row.change)));
        });
        add(section, body);
        if (list.length > SHOWN) {
          add(section, button('link more', open ? 'Show fewer' : 'Show all ' + list.length, function () {
            state.open[which.id] = !open;
            render();
          }));
        }
        return section;
      }

      // A day's figures beside its bar.
      function show(anchor, view, index) {
        var day = view.days[index], own = data.days[index];
        tip.textContent = '';
        add(tip, el('b', null, own.title), el('div', 'big', day.value));
        own.facts.forEach(function (fact) {
          add(tip, add(el('div', 'f'), el('span', null, fact.k), el('span', null, fact.v)));
        });
        var at = splitAt(view, state.by === 'total' ? 'model' : state.by);
        if (at >= 0) {
          var top = day.parts[at].map(function (part) {
            return { row: view.splits[at].rows[part.row], part: part };
          }).sort(function (a, b) { return b.part.amount - a.part.amount; }).slice(0, 4);
          if (top.length) add(tip, el('hr'));
          top.forEach(function (each) {
            add(tip, add(el('div', 'f'),
              add(el('span'), el('span', 'dot ' + each.row.hue), el('span', null, ' ' + each.row.name)),
              el('span', null, each.part.value)));
          });
        }
        place(anchor);
      }
      function place(anchor) {
        tip.hidden = false;
        var box = anchor.getBoundingClientRect(), mine = tip.getBoundingClientRect();
        var left = box.left + box.width / 2 - mine.width / 2;
        var top = box.top - mine.height - 8;
        tip.style.left = Math.max(8, Math.min(left, window.innerWidth - mine.width - 8)) + 'px';
        tip.style.top = (top < 8 ? box.bottom + 8 : top) + 'px';
      }
      function hide() { tip.hidden = true; }

      function render() {
        var view = data.views[state.unit];
        if (state.by !== 'total' && splitAt(view, state.by) < 0) state.by = 'total';
        live.textContent = '';
        add(live, lead(view), chart(view), picked(view), hours(view));
        view.splits.forEach(function (_, at) { live.appendChild(split(view, at)); });
        if (data.tokens.length) add(live, add(card('Tokens by kind', null), facts(data.tokens, 'tiles')));
        if (view.tiles.length) add(live, add(card('Highlights', null), facts(view.tiles, 'tiles')));
      }

      try {
        render();
        document.getElementById('static').hidden = true;
        live.hidden = false;
        window.addEventListener('scroll', hide, true);
      } catch (error) {
        live.hidden = true;
      }
    })();
    """#
}
