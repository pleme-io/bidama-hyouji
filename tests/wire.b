@moduledoc """
The kodou wire, proven end to end: each test writes a fixture project from `tests/wire`, locks it and runs it with the blue running these tests, then judges what the program printed, what a socket heard and the files it wrote.

    flash_rate #=> 16_384
"""

use("fairu", [:write_tree])
use("retsu", %i[first flat_map is_empty last push reject size])
use("shisutemu", %i[status_of stderr_of stdout_of])
use("tesuto", [:fresh_dir])

KENSA_FIXTURE = "aeba24d3e400593ba655d7b104a5edec5433cb919527111ffab8acab4620d21e"

SCHEMA = "kensa-immunity.v1"

@doc """
flash_rate: the bytes a second the host and kodou hold one wire's Flash channel to.

    flash_rate #=> 16_384
"""
def flash_rate()
  16384
end

@doc """
fixture: a path under this repository's `tests`, read from GEN_ROOT under the check and from the working directory otherwise.

    ends_with?(fixture("wire/flash.b"), "tests/wire/flash.b") #=> true
"""
def fixture(rel)
  path_join(path_join(getenv("GEN_ROOT", "."), "tests"), rel)
end

@doc """
scratch: a fresh empty directory under TMPDIR for one test.
"""
def scratch(name)
  fresh_dir("hyouji-wire-#{name}")
end

@doc """
blue: run the blue running these tests with `args`; the capture.
"""
def blue(args)
  exec_with_env([], self_exe, *args)
end

@doc """
blue_env: `blue` with extra environment variables.
"""
def blue_env(env, args)
  exec_with_env(env, self_exe, *args)
end

@doc """
allowing: the `--allow` arguments for each capability named.

    allowing(%w[clock none]) #=> ["--allow", "clock", "--allow", "none"]
"""
def allowing(caps)
  flat_map(caps, (c) -> ["--allow", c])
end

@doc """
project: a scratch project holding the Bluefile of `tests/wire/<kind>` and each [name, text] program, locked.
"""
def project(name, kind, programs)
  dir = scratch(name)
  write_tree(
    dir,
    push(programs, ["Bluefile", read_file(fixture("wire/#{kind}/Bluefile"))])
  )
  cap = blue(["lock", dir])
  if status_of(cap) != 0
    raise(:wire, "blue lock #{name}: #{stderr_of(cap)}")
  end
  dir
end

@doc """
program: a `tests/wire` program as a [name, text] pair.
"""
def program(name)
  [name, read_file(fixture("wire/#{name}"))]
end

@doc """
run: a project's program run quietly; its stdout read as JSON, and a failed run raised with its output.
"""
def run(dir, file)
  cap = blue(["run", "--quiet", path_join(dir, file)])
  if status_of(cap) != 0
    raise(:wire, "blue run #{file}: #{stdout_of(cap)}#{stderr_of(cap)}")
  end
  json_read(trim(stdout_of(cap)))
end

@doc """
every?: whether `pred` holds for each item of `xs`.

    every?((x) -> x > 0, [1, 2]) #=> true
    every?((x) -> x > 1, [1, 2]) #=> false
"""
def every?(pred, xs)
  is_empty(reject(pred, xs))
end

@doc """
rising?: whether each row's `at` column is above the row before it.

    rising?([[0, 1], [0, 2]], 1) #=> true
    rising?([[0, 2], [0, 2]], 1) #=> false
"""
def rising?(rows, at)
  every?(
    (i) -> rows[i + 1][at] > rows[i][at],
    range(blue::max(0, size(rows) - 1))
  )
end

@doc """
slice: the rows from index `from` up to, not including, `to`.

    slice([1, 2, 3, 4], 1, 3) #=> [2, 3]
"""
def slice(rows, from, to)
  take(to - from, drop(from, rows))
end

@doc """
over_rate: each [i, k] window of sends that spent more bytes than the rate and one burst allow between its first and last send.

    over_rate([[0, 100, 100]]) #=> []
"""
def over_rate(sends)
  n = size(sends)
  sums = reduce((acc, s) -> push(acc, last(acc) + s[1]), [0], sends)
  flat_map(
    range(n),
    fn(i)
      filter(
        fn(w)
          k = w[1]
          bytes = sums[k + 1] - sums[i]
          allowed = flash_rate * 1000 + flash_rate * (sends[k][0] - sends[i][0])
          bytes * 1000 > allowed
        end,
        map((k) -> [i, k], drop(i, range(n)))
      )
    end
  )
end

@doc """
listener: a UDP socket on a free port with both channels open on it, so it hears Flash and Tide frames alike.
"""
def listener()
  w = tide_open(flash_open("127.0.0.1:0"))
  {wire: w, port: last(split(flash_stats(w).address, ":"))}
end

@doc """
drained: every payload a read word answers until it waits 400 ms for none.
"""
def drained(next, acc)
  f = next()
  if f.nil?
    acc
  else
    drained(next, push(acc, f.payload))
  end
end

@doc """
heard: what a listener heard on each channel.
"""
def heard(l)
  {
    flash: drained(() -> flash_next(l.wire, 400), []),
    tide: drained(() -> tide_next(l.wire, 400), [])
  }
end

@doc """
breached: the breach program, sending to `port`, run with `allow`; the capture.
"""
def breached(dir, port, allow)
  write_tree(
    dir,
    [["breach.b", replace(read_file(fixture("wire/breach.b")), "PORT", port)]]
  )
  blue(append(%w[run --quiet], allowing(allow), [path_join(dir, "breach.b")]))
end

@doc """
canonical: JSON text with every object's keys sorted and no space, the form tameshi and kensa hash.

    canonical([1, nil, [true]]) #=> "[1,null,[true]]"
"""
def canonical(v)
  if map?(v)
    "{#{join(map((e) -> "#{json_stringify(e[0])}:#{canonical(e[1])}", map_entries(v)), ",")}}"
  elsif list?(v)
    "[#{join(map(canonical, v), ",")}]"
  else
    json_stringify(v)
  end
end

@doc """
b3: a text's content address, `b3:` and its BLAKE3 hash.

    b3("") #=> "b3:af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
"""
def b3(data)
  "b3:#{blake3_hex(data)}"
end

@doc """
be32: a length as four big-endian bytes.

    be32(258) #=> [0, 0, 1, 2]
"""
def be32(n)
  [
    floor(n / 16_777_216) % 256,
    floor(n / 65536) % 256,
    floor(n / 256) % 256,
    n % 256
  ]
end

@doc """
digest: the digest a `kensa-immunity.v1` file carries: BLAKE3 over the schema and the canonical entries, each its four-byte big-endian length then its bytes.
"""
def digest(entries)
  b3(
    flat_map(
      [SCHEMA, canonical(entries)],
      fn(f)
        b = text_bytes(f)
        append(be32(size(b)), b)
      end
    )
  )
end

@doc """
crash_from: the `.bluecrash` a `tests/wire` program leaves when it breaches under `--allow none`, run as `reader.b` in `dir`.
"""
def crash_from(dir, name)
  file = path_join(dir, "reader.b")
  write_tree(dir, [["reader.b", read_file(fixture("wire/#{name}"))]])
  traces = path_join(dir, "traces")
  cap = blue_env(
    [["BLUE_TRACE_DIR", traces]],
    ["run", "--quiet", "--allow", "none", file]
  )
  if status_of(cap) != 0
    raise(:wire, "blue run #{name}: #{stderr_of(cap)}")
  end
  crash = first(filter((p) -> ends_with?(p, ".bluecrash"), walk_dir(traces)))
  rm_rf(file)
  crash
end

@doc """
gossip: the gossip program: node a publishes each crash file to node b, then both step `rounds` times; b's known, refused and wanted count are printed.
"""
def gossip(crashes, immunity, rounds)
  reads = join(map((c) -> "read_file(\"#{c}\")", crashes), ", ")
  text = read_file(fixture("wire/gossip.b"))
  replace(
    replace(
      replace(
        replace(text, "IMMUNITY_A", replace(immunity, ".json", ".a.json")),
        "IMMUNITY",
        immunity
      ),
      "CRASHES",
      reads
    ),
    "ROUNDS",
    to_s(rounds)
  )
end

@doc """
immunity_file: the immunity file a node wrote, after its form is checked: canonical JSON of the schema kensa reads, carrying the digest of its entries.
"""
def immunity_file(path)
  text = read_file(path)
  file = json_read(text)
  assert text == canonical(file)
  assert file["schema"] == SCHEMA
  assert file["digest"] == digest(file["entries"])
  file
end

@doc """
kensa: the kensa binary KENSA_BIN names, or nil; with it, a gossiped file is checked against kensa's own.
"""
def kensa()
  k = getenv("KENSA_BIN")
  if k.nil? or not is_file?(k)
    nil
  else
    k
  end
end

@doc """
kensa_agrees: with kensa, the file `kensa immunize` writes for `crash` is `expected` byte for byte, and `kensa admit` refuses a deployment of `capability` whose definition the immunity file names, under both incident controls.
"""
def kensa_agrees(k, dir, crash, expected, immunity, entry)
  theirs = path_join(dir, "kensa-own.json")
  made = exec_with_env(
    [["KENSA_IMMUNITY", theirs]],
    k,
    "immunize",
    "--bluecrash",
    crash,
    "--immunity",
    theirs
  )
  assert status_of(made) == 0
  assert read_file(theirs) == expected
  cap = entry["capability"]
  write_tree(
    dir,
    [
      [
        "deployment.lock",
        json_stringify(
          {capabilities: {ceiling: [cap], floor: [cap], packages: {app: [cap]}}}
        )
      ],
      [
        "defs.json",
        json_stringify([{key: entry["definition"], hash: entry["def_hash"]}])
      ],
      ["ledger.json", ""],
      ["closure", ""]
    ]
  )
  verdict = json_read(
    trim(
      stdout_of(
        exec_with_env(
          [],
          k,
          "admit",
          "--lock",
          path_join(dir, "deployment.lock"),
          "--ledger",
          path_join(dir, "ledger.json"),
          "--profile",
          "low",
          "--json",
          "--closure",
          path_join(dir, "closure"),
          "--immunity",
          immunity,
          "--defs",
          path_join(dir, "defs.json")
        )
      )
    )
  )
  assert verdict["admitted"] == false
  refusal = {
    "kind" => "immune_crash",
    "crash_hash" => entry["crash_hash"],
    "def_hash" => entry["def_hash"],
    "capability" => cap
  }
  every?(
    fn(control)
      row = first(filter((r) -> r["control"] == control, verdict["controls"]))
      not row.nil? and member?(refusal, row["refusals"])
    end,
    %w[NIST_SP_800_53R5_IR_4 NIST_SP_800_53R5_IR_5]
  )
end

test "flash never exceeds its rate or its MTU and repeats under a stepped clock"
  dir = project("flash", "paced", [program("flash.b")])
  j = run(dir, "flash.b")
  sends = j["sends"]
  assert size(sends) == 40
  assert every?((s) -> s[1] <= 1280 and s[1] == s[2], sends)
  assert over_rate(sends) == []
  assert reduce((acc, s) -> acc + s[1], 0, sends) > flash_rate
  assert last(sends)[0] > 0
  assert j["bucket"] == "refused"
  assert j["host"] == "refused"
  assert j["sent"] == 40
  assert j["received"] == 40
  assert j["refused"] == 0
  assert run(dir, "flash.b") == j
  rm_rf(dir)
end

test "the paced flash program replays over the loopback with the schedule it had over UDP"
  udp = project("replay-udp", "paced", [program("flash.b")])
  looped = project("replay-loop", "replayed", [program("flash.b")])
  over_udp = run(udp, "flash.b")
  over_loopback = run(looped, "flash.b")
  assert over_loopback == over_udp
  assert over_loopback["refused"] == 0
  rm_rf(udp)
  rm_rf(looped)
end

test "tide collapses to its floor two ms over its base delay and recovers"
  dir = project("tide", "paced", [program("tide.b")])
  j = run(dir, "tide.b")
  floor = j["floor"]
  assert floor == 2560
  rows = j["rows"]
  assert size(rows) == 15
  base = slice(rows, 0, 5)
  one_over = slice(rows, 5, 8)
  two_over = slice(rows, 8, 11)
  recovered = slice(rows, 11, 15)
  assert rising?(base, 1)
  assert every?((r) -> r[2] == 0, base)
  assert every?((r) -> r[1] > floor, one_over)
  assert every?((r) -> r[1] == floor and r[2] == 2, two_over)
  assert every?((r) -> r[1] > floor and r[2] == 0, recovered)
  assert rising?(recovered, 1)
  rm_rf(dir)
end

test "a frame without comm-flash breaches with 77 and sends nothing"
  dir = scratch("breach")
  l = listener
  o = breached(dir, l.port, %w[comm_scavenger clock comm_flash])
  assert status_of(o) == 0
  assert stdout_of(o) == "after"
  assert heard(l) == {flash: ["alert"], tide: ["dcontrol"]}
  l = listener
  o = breached(dir, l.port, %w[comm_scavenger clock])
  assert status_of(o) == 77
  assert contains?(stderr_of(o), "`flash_open` reaches the host (comm-flash)")
  assert not contains?(stdout_of(o), "swallowed")
  assert not contains?(stdout_of(o), "after")
  assert heard(l) == {flash: [], tide: ["dcontrol"]}
  l = listener
  o = breached(dir, l.port, ["none"])
  assert status_of(o) == 77
  assert contains?(stderr_of(o), "(comm-scavenger)")
  assert heard(l) == {flash: [], tide: []}
  locked = scratch("breach-lock")
  write_tree(
    locked,
    [
      ["Bluefile", read_file(fixture("wire/locked/Bluefile"))],
      ["breach.b", replace(read_file(fixture("wire/breach.b")), "PORT", "9")]
    ]
  )
  o = blue(["lock", locked])
  assert status_of(o) != 0
  assert contains?(
    stderr_of(o),
    "[wire-breach] -> [hyouji/kodou::link: needs 'comm-flash'] violates ceiling [clock, comm-scavenger]"
  )
  rm_rf(dir)
  rm_rf(locked)
end

test "a gossiped crash proof arrives, verifies and yields the immunity entry kensa refuses on"
  dir = scratch("gossip")
  known_crash = fixture("fixtures/#{KENSA_FIXTURE}.bluecrash")
  fresh = crash_from(dir, "reader.b")
  immunity = path_join(dir, "kensa-immunity.json")
  node = project(
    "gossip-node",
    "gossiped",
    [["first.b", gossip([known_crash], immunity, 8)]]
  )
  j = run(node, "first.b")
  known_hash = "b3:#{KENSA_FIXTURE}"
  assert j["known"] == [known_hash]
  assert j["refused"] == []
  assert j["wanted"] == 0
  first_text = read_file(immunity)
  write_tree(node, [["second.b", gossip([fresh, known_crash], immunity, 8)]])
  j = run(node, "second.b")
  fresh_text = read_file(fresh)
  fresh_hash = b3(canonical(json_read(fresh_text)))
  assert size(j["known"]) == 2
  assert member?(fresh_hash, j["known"])
  file = immunity_file(immunity)
  hashes = map((e) -> e["crash_hash"], file["entries"])
  assert hashes == sort_keyed((h) -> h, [known_hash, fresh_hash])
  assert b3(canonical(json_read(read_file(known_crash)))) == known_hash
  fresh_doc = json_read(fresh_text)
  fresh_entry = first(
    filter((e) -> e["crash_hash"] == fresh_hash, file["entries"])
  )
  assert fresh_entry ==
    {
      "capability" => "filesystem",
      "class" => "LatticeCeilingBreach",
      "crash_hash" => fresh_hash,
      "def_hash" => fresh_doc["def_hash"],
      "definition" => "%root/reader",
      "host" => "is_file?"
    }
  k = kensa
  if not k.nil?
    assert kensa_agrees(k, dir, known_crash, first_text, immunity, fresh_entry)
  end
  rm_rf(dir)
  rm_rf(node)
end

test "a gossiped comm-flash breach yields an immunity entry kensa reads"
  dir = scratch("gossip-flash")
  crash = crash_from(dir, "flasher.b")
  crash_text = read_file(crash)
  crash_doc = json_read(crash_text)
  assert crash_doc["violation"]["capability"] == "comm-flash"
  crash_hash = b3(canonical(crash_doc))
  immunity = path_join(dir, "kensa-immunity.json")
  node = project(
    "gossip-flash-node",
    "gossiped",
    [["flash.b", gossip([crash], immunity, 40)]]
  )
  j = run(node, "flash.b")
  assert j["known"] == [crash_hash]
  assert j["refused"] == []
  file = immunity_file(immunity)
  entry = {
    "capability" => "comm-flash",
    "class" => "LatticeCeilingBreach",
    "crash_hash" => crash_hash,
    "def_hash" => crash_doc["def_hash"],
    "definition" => "%root/flasher",
    "host" => "flash_open"
  }
  assert file["entries"] == [entry]
  k = kensa
  if not k.nil?
    assert kensa_agrees(k, dir, crash, read_file(immunity), immunity, entry)
  end
  rm_rf(dir)
  rm_rf(node)
end
