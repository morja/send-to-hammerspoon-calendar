local failures = 0
local alerts = {}
local asyncRequest = nil
local server = nil
local preview = nil

local function check(name, condition)
    if condition then
        print("ok - " .. name)
    else
        failures = failures + 1
        print("not ok - " .. name)
    end
end

local function newServer(ssl, bonjour)
    local instance = {
        ssl = ssl,
        bonjour = bonjour,
        stopped = false,
    }

    function instance:setInterface(value)
        self.interface = value
        return self
    end

    function instance:setPort(value)
        self.port = value
        return self
    end

    function instance:maxBodySize(value)
        self.bodySize = value
        return self
    end

    function instance:setCallback(value)
        self.callback = value
        return self
    end

    function instance:start()
        self.started = true
        return self
    end

    function instance:stop()
        self.stopped = true
    end

    server = instance
    return instance
end

hs = {
    alert = {
        show = function(message)
            table.insert(alerts, message)
        end,
    },
    httpserver = { new = newServer },
    http = {
        asyncPost = function(url, body, headers, callback)
            asyncRequest = { url = url, body = body, headers = headers, callback = callback }
        end,
    },
    json = {
        encode = function()
            return "{}"
        end,
        decode = function(value)
            if value == "valid-response" then
                return {
                    choices = {
                        { message = { content = "valid-event" } },
                    },
                }
            end

            if value == "valid-event" then
                return {
                    title = "Visible preview",
                    start = "2030-04-12T09:30:00",
                    ["end"] = "2030-04-12T10:30:00",
                    all_day = false,
                    calendar = "",
                    location = "",
                    notes = "",
                }
            end

            return nil
        end,
    },
    hotkey = {
        bind = function()
            error("hotkey should be disabled in this test")
        end,
    },
    pasteboard = { getContents = function() return nil end },
    screen = {
        mainScreen = function()
            return {
                frame = function()
                    return { x = 0, y = 0, w = 1600, h = 1000 }
                end,
            }
        end,
    },
    webview = {
        usercontent = {
            new = function()
                return {
                    setCallback = function(self, callback)
                        self.callback = callback
                        return self
                    end,
                }
            end,
        },
        new = function()
            local instance = {}
            for _, method in ipairs({ "windowTitle", "allowTextEntry", "windowStyle", "deleteOnClose", "windowCallback", "html" }) do
                instance[method] = function(self)
                    return self
                end
            end
            function instance:show()
                self.shown = true
                return self
            end
            function instance:bringToFront(aboveEverything)
                self.broughtToFront = true
                self.aboveEverything = aboveEverything
                return self
            end
            function instance:hswindow()
                return {
                    focus = function()
                        self.focused = true
                    end,
                }
            end
            function instance:delete()
                self.deleted = true
            end
            preview = instance
            return instance
        end,
    },
    printf = function() end,
}

local Integration = dofile("src/send_to_hammerspoon.lua")
local started = Integration.start({
    serviceConfigFile = "tests/fixtures/service.fixture",
    openRouterKeyFile = "tests/fixtures/api-key.fixture",
    hotkey = { enabled = false },
})

check("starts with test configuration", started == true)
check("disables TLS only for loopback transport", server.ssl == false)
check("disables Bonjour advertisement", server.bonjour == false)
check("binds only to localhost", server.interface == "localhost")
check("loads local service port", server.port == 18492)
check("enforces body limit", server.bodySize == 50000)

local _, wrongPathStatus = server.callback("POST", "/wrong", {}, "Example")
check("rejects unknown endpoint", wrongPathStatus == 404)

local _, unauthorizedStatus = server.callback("POST", "/event", {}, "Example")
check("rejects missing token", unauthorizedStatus == 401)

local headers = {
    ["x-send-to-hammerspoon-token"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
}
local _, emptyStatus = server.callback("POST", "/event", headers, "  ")
check("rejects empty text", emptyStatus == 409)

local _, acceptedStatus = server.callback("POST", "/event", headers, "Meet Thursday at 10")
check("accepts authenticated text", acceptedStatus == 202)
check("sends only to OpenRouter HTTPS endpoint", asyncRequest.url == "https://openrouter.ai/api/v1/chat/completions")

local _, busyStatus = server.callback("POST", "/event", headers, "Second request")
check("rejects concurrent extraction", busyStatus == 409)

asyncRequest.callback(500, "bad response")
local _, acceptedAfterCallback = server.callback("POST", "/event", headers, "Try again")
check("clears busy state after response", acceptedAfterCallback == 202)
asyncRequest.callback(200, "valid-response")
check("shows extracted preview", preview and preview.shown == true)
check("raises preview above full-screen apps", preview and preview.aboveEverything == true)
check("focuses preview window", preview and preview.focused == true)

Integration.stop()
check("stops local receiver", server.stopped == true)

local missingKeyStarted = Integration.start({
    serviceConfigFile = "tests/fixtures/service.fixture",
    openRouterKeyFile = "tests/fixtures/does-not-exist.fixture",
    hotkey = { enabled = false },
})
local _, missingKeyStatus = server.callback("POST", "/event", headers, "Example")
check("can start before key is configured", missingKeyStarted == true)
check("reports missing key to Service", missingKeyStatus == 409)

Integration.stop()
os.exit(failures == 0 and 0 or 1)
