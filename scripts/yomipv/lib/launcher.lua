--[[ Launcher                                  ]]
--[[ Handles launching the Electron lookup app ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local Platform = require("lib.platform")

local Launcher = {}

function Launcher.launch_lookup_app(_config)
	local app_path = "lookup-app"

	-- Resolve relative paths against the script directory
	if not app_path:find(":") and not app_path:find("^/") then
		app_path = utils.join_path(mp.get_script_directory(), app_path)
	end

	msg.info("Launching lookup app from: " .. app_path)

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = {
			Platform.get_curl_cmd(),
			"-s",
			"-o",
			Platform.get_null_device(),
			"--connect-timeout",
			"1",
			"http://127.0.0.1:19634/",
		},
	}, function(success, result, _error)
		-- Skip launch if the application endpoint is already responsive
		if success and result.status == 0 then
			msg.info("Lookup app already running, skipping startup")
			return
		end

		local mpv_pid = utils.getpid()
		local ipc_pipe = mp.get_property("input-ipc-server")

		-- Ensure a valid IPC server is available for Electron communication
		if not (ipc_pipe and ipc_pipe ~= "") then
			if Platform.IS_WINDOWS then
				ipc_pipe = "\\\\.\\pipe\\yomipv-" .. mpv_pid
			elseif Platform.IS_MACOS or Platform.IS_LINUX then
				ipc_pipe = "/tmp/yomipv-" .. mpv_pid
			end
			mp.set_property("input-ipc-server", ipc_pipe)
		end

		local electron_ipc_pipe = ipc_pipe
		if Platform.IS_WINDOWS and not electron_ipc_pipe:match("^\\\\.\\pipe\\") then
			electron_ipc_pipe = "\\\\.\\pipe\\" .. electron_ipc_pipe
		end

		Platform.launch_electron_app(
			app_path,
			mpv_pid,
			electron_ipc_pipe,
			function(launch_success, _launch_result, launch_error)
				if not launch_success then
					msg.error("Failed to launch lookup app: " .. tostring(launch_error))
				end
			end
		)
	end)
end

function Launcher.shutdown_lookup_app()
	msg.info("Sending shutdown signal to lookup app")
	local ok, result = pcall(mp.command_native, {
		name = "subprocess",
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
		args = {
			Platform.get_curl_cmd(),
			"-s",
			"-X",
			"POST",
			"--connect-timeout",
			"1",
			"--max-time",
			"1",
			"http://127.0.0.1:19634/shutdown",
		},
	})
	if not ok then
		msg.warn("Lookup app shutdown request failed: " .. tostring(result))
	elseif result and result.status ~= 0 then
		msg.warn("Lookup app shutdown request exited with status: " .. tostring(result.status))
	end
end

return Launcher
