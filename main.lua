--- @since 26.1.22

local function fail(s, ...)
	ya.notify {
		title = "Chmod",
		content = string.format(s, ...),
		level = "error",
		timeout = 5,
	}
end

local selected_or_hovered = ya.sync(function()
	local tab, paths = cx.active, {}
	for _, u in pairs(tab.selected) do
		paths[#paths + 1] = tostring(u)
	end
	if #paths == 0 and tab.current.hovered then
		paths[1] = tostring(tab.current.hovered.url)
	end
	return paths
end)

local toggle_ui = ya.sync(function(self)
	if self.children then
		Modal:children_remove(self.children)
		self.children = nil
	else
		self.children = Modal:children_add(self, 10)
	end
	ui.render()
end)

local M = {
	keys = {
		{ on = "q",           run = "quit" },
		{ on = "<Esc>",       run = "quit" },
		{ on = "<Enter>",     run = "enter" },
		{ on = "<Backspace>", run = "back" },

		{ on = "k",           run = "up" },
		{ on = "j",           run = "down" },
		{ on = "l",           run = "enter" },
		{ on = "h",           run = "back" },
		{ on = "y",           run = "enter" },

		{ on = "<Up>",        run = "up" },
		{ on = "<Down>",      run = "down" },
		{ on = "<Right>",     run = "enter" },
		{ on = "<Left>",      run = "back" },
	},
	commands = {
		"sha1sum",
		"sha256sum",
		"sha512sum",
		"md5sum",
	},
}

local set_state = ya.sync(function(self, nstate)
	for k, v in pairs(nstate) do
		self[k] = v
	end
end)

local get_state = ya.sync(function(self, field)
	return self[field]
end)

local reset_state = ya.sync(function(self)
	set_state({
		cursor = 0,
		mode = "command",
		selected = "",
		hashes = {},
	})
end)

local update_cursor = ya.sync(function(self, delta)
	if self.mode == "command" then
		self.cursor = (self.cursor + delta) % #M.commands
	elseif self.mode == "display" then
		self.cursor = (self.cursor + delta) % math.max(1, #self.hashes)
	end
end)

local handle_enter = ya.sync(function(self)
	if self.mode == "command" then
		self.mode = "display"
		self.selected = M.commands[self.cursor + 1]
	elseif self.mode == "display" then
		-- yank code
	end
end)

function M:new(area)
	self:layout(area)
	return self
end

function M:layout(area)
	local chunks = ui.Layout()
			:constraints({
				ui.Constraint.Percentage(10),
				ui.Constraint.Percentage(80),
				ui.Constraint.Percentage(10),
			})
			:split(area)

	local chunks = ui.Layout()
			:direction(ui.Layout.HORIZONTAL)
			:constraints({
				ui.Constraint.Percentage(10),
				ui.Constraint.Percentage(80),
				ui.Constraint.Percentage(10),
			})
			:split(chunks[2])

	self._area = chunks[2]
end

function M:entry(job)
	reset_state()
	toggle_ui()

	local tx, rx = ya.chan("mpsc")
	function producer()
		while true do
			local cand = self.keys[ya.which { cands = self.keys, silent = true }] or { run = {} }
			for _, r in ipairs(type(cand.run) == "table" and cand.run or { cand.run }) do
				tx:send(r)
				if r == "quit" then
					toggle_ui()
					reset_state()
					return
				end
			end
		end
	end

	function consumer()
		repeat
			local run = rx:recv()
			if run == "quit" then
				break
			elseif run == "up" then
				update_cursor(-1)
			elseif run == "down" then
				update_cursor(1)
			elseif run == "enter" then
				if get_state("mode") == "command" then
					handle_enter()
					if #get_state("hashes") == 0 then
						local sel, hsh = selected_or_hovered(), {}

						for _, f in ipairs(sel) do
							local out, err = Command(get_state("selected")):arg(f):output()

							if not out then
								fail("failed to run %s: %s", get_state("selected"), err)
								hsh[#hsh + 1] = {
									name = f,
									hash = "-1",
									status = "?",
								}
							elseif not out.status.success then
								fail("failed to run %s: %s", get_state("selected"), out.stderr)
								hsh[#hsh + 1] = {
									name = f,
									hash = "-1",
									status = "?",
								}
							else
								local val = ""
								for i = 1, #out.stdout do
									local ch = out.stdout:sub(i, i)
									if not ch:match("[0-9a-fA-F]") then
										break
									end
									val = val .. ch
								end

								-- get filename
								local fname = f:match("([^/\\]+)$") or f

								local dir = Url(f).parent
								local ext = "." .. get_state("selected")
								local expected = nil

								for _, entry in ipairs(fs.read_dir(dir, { glob = "*" .. ext }) or {}) do
									out, err = Command("cat"):arg(tostring(entry.url)):output()
									if not out or not out.status.success then
										break
									end
									local content = out.stdout
									if content then
										for line in content:gmatch("[^\r\n]+") do
											local h, name = line:match("^([0-9a-fA-F]+)%s+(.+)$")
											if h and name then
												local base = name:match("([^/\\]+)$") or name
												if base == fname then
													expected = h
													break
												end
											end
										end
									end
									if expected then break end
								end

								local status = expected and (expected == val and "OK" or "NG") or "?"

								hsh[#hsh + 1] = {
									name = fname,
									hash = val,
									status = status,
								}
							end
						end
						set_state({ hashes = hsh })
					end
				elseif get_state("mode") == "display" then
					handle_enter()
					local child, err = Command("xclip")
							:arg { "-selection", "clipboard" }
							:stdin(Command.PIPED)
							:spawn()
					if not child then
						fail("failed to spawn xclip: %s", err)
					end
					local res = false
					res, err = child:write_all(get_state("hashes")[get_state("cursor") + 1].hash)
					if not res then
						fail("failed to run xclip: %s", err)
					end
					res, err = child:flush()
					if not res then
						fail("failed to run xclip: %s", err)
					end
					res, err = child:wait()
					if not res then
						fail("failed to run xclip: %s", err)
					elseif not res.success then
						fail("failed to run xclip: %s", res.code)
					end
				end
			elseif run == "back" then
				if get_state("mode") == "display" then
					set_state({ mode = "command", hashes = {} })
				end
			else
				ya.dbg("checksum.yazi: unknown message " .. run)
			end
		until not run
	end

	ya.join(producer, consumer)
end

function M:reflow() return { self } end

function M:redraw()
	local rows = {}
	if get_state("mode") == "command" then
		for _, c in ipairs(self.commands or {}) do
			rows[#rows + 1] = ui.Row { c }
		end
	elseif get_state("mode") == "display" then
		for _, h in ipairs(get_state("hashes") or {}) do
			rows[#rows + 1] = ui.Row { h.name or "", "", h.hash or "", "", h.status or "?" }
		end
	end

	local tbl = ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 2, 1, 2)))
			:row(get_state("cursor"))
			:row_style(ui.Style():fg("blue"):underline())

	if get_state("mode") == "command" then
		tbl
				:header(ui.Row({ "commands" }):style(ui.Style():bold()))
	elseif get_state("mode") == "display" then
		tbl
				:header(ui.Row({ "name", "", "hash", }):style(ui.Style():bold()))
				:widths {
					ui.Constraint.Percentage(40),
					ui.Constraint.Length(1), -- padding so they don't clump together
					ui.Constraint.Fill(1),
					ui.Constraint.Length(1), -- padding so they don't clump together
					ui.Constraint.Length(2),
				}
	end

	ui.render()

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
				:area(self._area)
				:type(ui.Border.ROUNDED)
				:style(ui.Style():fg("blue"))
				:title(ui.Line("Mount"):align(ui.Align.CENTER)),
		tbl,
	}
end

function M:click() end

function M:scroll() end

function M:touch() end

return M
