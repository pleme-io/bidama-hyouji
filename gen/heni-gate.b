@moduledoc """
The mutation gate: each `heni/mutations/<key>.json` names mutations of the bidama package at `bidamas/<key>`, heni runs that package's tests against each one, and the share it catches may never fall below the row `heni/ratio.baseline` records for the key. `blue gen/heni-gate.b record` writes the rows; a fall needs `--receipt "<why>"`.

    key_of("heni/mutations/hyouji/kodou.json") #=> "hyouji/kodou"
"""

use("hadome", %i[measurement orphans parse recorded render])
use("heni", %i[fell? mutations report_text run score sound? survivors])
use("moji", [:trim])
use("retsu", %i[flat_map is_empty last size])
use("shisutemu", [:read_or])

CAUGHT = "heni-caught"

TOTAL = "heni-total"

RECORD = "blue gen/heni-gate.b record"

@doc """
root: the repository the gate reads: GEN_ROOT under the check, the working directory otherwise.
"""
def root()
  getenv("GEN_ROOT", ".")
end

@doc """
specs: every mutation file, sorted by path.
"""
def specs()
  filter(
    (p) -> ends_with?(p, ".json"),
    sort_keyed((p) -> p, walk_dir(path_join(root, "heni/mutations")))
  )
end

@doc """
key_of: the package key a mutation file names: its path below `heni/mutations/`, without `.json`.

    key_of("/r/heni/mutations/fuuin.json") #=> "fuuin"
"""
def key_of(spec_path)
  replace(last(split(spec_path, "heni/mutations/")), ".json", "")
end

@doc """
package_of: the package directory a key names, under `bidamas`.

    ends_with?(package_of("hyouji/kodou"), "bidamas/hyouji/kodou") #=> true
"""
def package_of(key)
  path_join(path_join(root, "bidamas"), key)
end

@doc """
baseline_path: where the recorded caught ratios live.
"""
def baseline_path()
  path_join(root, "heni/ratio.baseline")
end

@doc """
report: heni's run of one mutation file against its package, with the blue running this gate.
"""
def report(spec_path)
  run(
    {
      package: package_of(key_of(spec_path)),
      mutations: mutations(json_parse(read_file(spec_path))),
      blue: self_exe,
      test: nil,
      tmp: getenv("TMPDIR", "/tmp")
    }
  )
end

@doc """
ratio_text: a caught ratio as text.

    ratio_text({caught: 2, total: 3}) #=> "2/3"
"""
def ratio_text(q)
  "#{to_s(q[:caught])}/#{to_s(q[:total])}"
end

@doc """
recorded_ratio: the ratio the baseline records for a key, or nil.

    recorded_ratio([], "fuuin") #=> nil
"""
def recorded_ratio(rows, key)
  c = recorded(rows, CAUGHT, key)
  t = recorded(rows, TOTAL, key)
  if c.nil? or t.nil?
    nil
  else
    {caught: c, total: t}
  end
end

@doc """
problems: why one measured package fails the gate: an unsound run, no recorded row, or a fall below its row, naming each survivor.
"""
def problems(rows, key, r)
  if not sound?(r)
    ["#{key}: #{trim(report_text(r))}"]
  else
    was = recorded_ratio(rows, key)
    now = score(r)
    if was.nil?
      [
        "#{key}: caught #{ratio_text(now)} and the baseline has no row for it; record it: #{RECORD}"
      ]
    elsif fell?(was, now)
      [
        "#{key}: caught #{ratio_text(now)}, below its recorded #{ratio_text(was)}; survived: #{join(survivors(r), ", ")}"
      ]
    else
      []
    end
  end
end

@doc """
judge: every problem of every measured package.
"""
def judge(rows, measured)
  flat_map(measured, (m) -> problems(rows, m[:key], m[:r]))
end

@doc """
measure: heni's report for each mutation file, keyed.
"""
def measure(paths)
  map((s) -> {key: key_of(s), r: report(s)}, paths)
end

@doc """
rendered: the baseline rows for what was measured.
"""
def rendered(measured)
  join(
    map(
      fn(m)
        q = score(m[:r])
        concat(
          render(CAUGHT, [measurement(m[:key], q[:caught])]),
          render(TOTAL, [measurement(m[:key], q[:total])])
        )
      end,
      sort_keyed((m) -> m[:key], measured)
    ),
    ""
  )
end

@doc """
baseline_text: the new baseline: the old comment lines, the receipt when one is given, then the rows.
"""
def baseline_text(old, receipt, measured)
  notes = append(
    filter((l) -> starts_with?(l, "#"), split(old, line_break)),
    if receipt.nil?
      []
    else
      ["# receipt: #{receipt}"]
    end
  )
  if is_empty(notes)
    rendered(measured)
  else
    concat(unlines(notes), rendered(measured))
  end
end

@doc """
record: measure every package and write the baseline; an unsound run records nothing, and a fall records only with a receipt.
"""
def record(receipt)
  rows = parse(read_or(baseline_path, ""))
  measured = measure(specs)
  bad = judge([], filter((m) -> not sound?(m[:r]), measured))
  fell = filter(
    fn(m)
      was = recorded_ratio(rows, m[:key])
      was != nil and fell?(was, score(m[:r]))
    end,
    measured
  )
  if not is_empty(bad)
    write_stderr(
      unlines(
        retsu::push(bad, "refused: a run that is not sound records nothing")
      )
    )
    exit_with(1)
  elsif not is_empty(fell) and receipt.nil?
    write_stderr(
      unlines(
        retsu::push(
          judge(rows, fell),
          "refused: a fall needs a reason: #{RECORD} --receipt \"<why>\""
        )
      )
    )
    exit_with(1)
  else
    write_file(
      baseline_path,
      baseline_text(read_or(baseline_path, ""), receipt, measured)
    )
    write_stdout(
      unlines(
        ["recorded #{to_s(size(measured))} package(s) to #{baseline_path}"]
      )
    )
  end
end

def main()
  if argv_get(0) == "record"
    at = position("--receipt", argv)
    record(
      if at < 0
        nil
      else
        argv_get(at + 1)
      end
    )
  else
    write_stderr(unlines(["usage: #{RECORD} [--receipt WHY]"]))
    exit_with(64)
  end
end

test "every package holds its recorded caught ratio"
  rows = parse(read_or(baseline_path, ""))
  assert not is_empty(specs)
  assert orphans(rows, CAUGHT, map(key_of, specs)) == []
  bad = judge(rows, measure(specs))
  if not is_empty(bad)
    write_stderr(unlines(bad))
  end
  assert is_empty(bad)
end

def fixture_run(verdicts)
  {
    control: 0,
    refused: 0,
    blind: 0,
    results: map((v) -> {name: "m-#{to_s(v[0])}", verdict: v[1]}, verdicts)
  }
end

test "a survivor below the recorded ratio names its package and itself"
  rows = parse(unlines(["heni-caught: kazu 2", "heni-total: kazu 2"]))
  held = fixture_run([[0, :caught], [1, :caught]])
  assert judge(rows, [{key: "kazu", r: held}]) == []
  fell = fixture_run([[0, :caught], [1, :survived]])
  assert judge(rows, [{key: "kazu", r: fell}]) ==
    ["kazu: caught 1/2, below its recorded 2/2; survived: m-1"]
  assert judge([], [{key: "kazu", r: held}]) ==
    ["kazu: caught 2/2 and the baseline has no row for it; record it: blue gen/heni-gate.b record"]
end
