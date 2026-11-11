use("hyouji/kodou", %i[address link pump queue take])
use("ibuki", %i[floor_window queuing])
use("retsu", [:push])

def stocked(l, peer, chunk)
  short = blue::max(0, 24 - tide_stats(l.wire).queued)
  reduce((acc, _i) -> queue(acc, peer, chunk), l, range(short))
end

def drained(l, refill)
  reduce(
    fn(acc, _i)
      if acc.idle
        acc
      else
        t = take(acc.link, 50)
        moved = if refill
          pump(t.link)
        else
          t.link
        end
        {link: moved, idle: t.idle}
      end
    end,
    {link: l, idle: false},
    range(400)
  ).link
end

def round(acc, d, peer, chunk)
  a = pump(stocked(acc.a, peer, chunk))
  sleep_ms(d)
  b = drained(acc.b, false)
  moved = drained(a, true)
  {
    a: moved,
    b:,
    rows: push(acc.rows, [d, moved.tide.cwnd, queuing(moved.tide)])
  }
end

def main()
  a = link("127.0.0.1:0", {channels: [:tide]})
  b = link("127.0.0.1:0", {channels: [:tide]})
  chunk = join(map((_k) -> "x", range(1000)), "")
  plan = [5, 5, 5, 5, 5, 6, 6, 6, 7, 7, 7, 5, 5, 5, 5]
  done = reduce(
    (acc, d) -> round(acc, d, address(b), chunk),
    {a:, b:, rows: []},
    plan
  )
  write_stdout(json_stringify({floor: floor_window(a.tide), rows: done.rows}))
end
