-- AI-vs-AI balance simulation: every difficulty pair (seats alternated) and
-- every personality against a Standard Ledger. Prints win-rate tables used to
-- tune the tiers.   luaurun tests/run.luau sim [matchesPerPair]

return function(H, args)
	local n = tonumber(args[2]) or 80
	local order = { "Casual", "Standard", "Advanced", "Expert" }
	print(string.format("\n== AI simulation (%d matches per pair, row = win rate vs column)", n))
	local header = string.format("%-10s", "")
	for _, col in order do
		header ..= string.format("%10s", col)
	end
	print(header)
	for _, row in order do
		local line = string.format("%-10s", row)
		for _, col in order do
			local wins = 0
			for seed = 1, n do
				local rowSeat = seed % 2 == 0 and 1 or 2
				local winner
				if rowSeat == 1 then
					winner = H.duel(row, col, "Ledger", "Ledger", seed * 7 + #row * 3 + #col)
				else
					winner = H.duel(col, row, "Ledger", "Ledger", seed * 7 + #row * 3 + #col)
				end
				if winner == rowSeat then
					wins += 1
				end
			end
			line ..= string.format("%9d%%", math.floor(wins / n * 100 + 0.5))
		end
		print(line)
	end
	print("\n== Personalities on Advanced vs Standard Ledger")
	for _, persona in { "Ledger", "Volta", "Magpie", "Kismet", "Proctor" } do
		local wins = 0
		for seed = 1, n do
			local seat = seed % 2 == 0 and 1 or 2
			local winner
			if seat == 1 then
				winner = H.duel("Advanced", "Standard", persona, "Ledger", seed * 11)
			else
				winner = H.duel("Standard", "Advanced", "Ledger", persona, seed * 11)
			end
			if winner == seat then
				wins += 1
			end
		end
		print(string.format("  %-8s %3d%%", persona, math.floor(wins / n * 100 + 0.5)))
	end
end
