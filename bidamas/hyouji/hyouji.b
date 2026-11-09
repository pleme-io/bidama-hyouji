@moduledoc """
hyouji (表示, display): the blue bidamas for what a program shows: the browser, the paced wire and motion. Each is a level of this tree, reached as `hyouji::<level>::<word>` after `use("hyouji/<level>")`.

    length(members) #=> 3
"""

@doc """
members: the levels of hyouji, in the order they joined it.

    nth(0, members) #=> "burauza"
"""
def members()
  %w[burauza kodou ugoki]
end

test "members names each level once"
  assert length(members) == 3
  assert members[0] == "burauza"
end
