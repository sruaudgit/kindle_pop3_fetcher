--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.pop3_fetcher
--]]--


local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")


local socket = require("socket")
local ssl = require("ssl")
local ltn12 = require("ltn12")
local logger = require("logger")

local Pop3 = WidgetContainer:extend{
    name = "pop3_fetcher",
    pop3_server = "tdb",  -- e.g., "pop.gmail.com"
    pop3_port = 995,                -- Standard POP3 SSL port
    username   = "tbd",
    password = "tbd",  -- Use app-specific password for 2FA accounts
    save_dir = "/mnt/us/ebooks/pop3" 
}

function Pop3:onDispatcherRegisterActions()
    Dispatcher:registerAction("pop3_fetch", {category="none", event="Pop3Fetch", title=_("Pop3"), general=true,})
end


function Pop3:init()
	logger.info("Pop3 fetcher init")

    self.config = LuaSettings:open( "./pop3_cfg.lua")
    if next(self.config.data) == nil then
        self.updated = true -- first run, force flush
    end
    self.pop3_server = self.config:readSetting("pop3_server", self.pop3_server)
    logger.info("Pop3 fetcher pop3_server "..self.pop3_server)
    self.pop3_port = self.config:readSetting("pop3_port", self.pop3_port)
    logger.info("Pop3 fetcher pop3_port "..self.pop3_port)
    self.username = self.config:readSetting("username", self.username)
    logger.info("Pop3 fetcher username "..self.username)
    self.password = self.config:readSetting("password", self.password)
    self.save_dir = self.config:readSetting("save_dir", self.save_dir)
    logger.info("Pop3 fetcher save_dir "..self.save_dir)

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)


 	self:onDispatcherRegisterActions()
    	self.ui.menu:registerToMainMenu(self)
end

function Pop3:addToMainMenu(menu_items)
    logger.info("Pop3 fetcher addToMainMenu")
    menu_items.pop3 = {
        text = _("Pop3 Fetcher"),
        -- in which menu this should be appended
        sorting_hint = "more_tools",
        -- a callback when tapping
        callback = function()
		self:main()
        end,
    }
end

function Pop3:onPop3Fetch()
    local popup = InfoMessage:new{
        text = _("Hello From Pop3 iFetcher"),
    }
    UIManager:show(popup)
end


-- Create save directory if it doesn't exist
function Pop3:create_save_dir()
    logger.info("Pop3 fetcher create_save_dir")
    local cmd = string.format('mkdir "%s"', self.save_dir)
    os.execute(cmd)
end

-- Base64 decoding (simplified for attachments)
function Pop3:base64_decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

-- Parse email to extract attachments


-- Main function
function Pop3:main()
    logger.info("Pop3 fetcher main")
    self:create_save_dir()

    -- Step 1: Create TCP connection
    logger.info("Pop3 fetcher connect")
    local tcp = socket.tcp()
    tcp:connect(self.pop3_server, self.pop3_port)
    if not tcp then error("Failed to connect to POP3 server") end
    logger.info("Pop3 fetcher connect ok")

    -- Step 2: Wrap with SSL/TLS
    local params = {
        mode = "client",
        protocol = "tlsv1_2",  -- Use modern TLS
        verify = "none",       -- Kindle may lack CA certs; disable verification
        options = "all"
    }
    logger.info("Pop3 fetcher wrapping ssl")
    local ssl_conn, err = ssl.wrap(tcp, params)
    if not ssl_conn then error("SSL wrap failed: "..err) end
    logger.info("Pop3 fetcher handshake ssl")
    ssl_conn:dohandshake()  -- Perform SSL handshake

    ssl_conn:settimeout(10)  -- Set timeout for read operations

    -- Step 3: Authenticate with POP3
    local response = ssl_conn:receive()  -- Read server greeting
    logger.info("Pop3 fetcher "..response)
    ssl_conn:send("USER "..self.username.."\r\n")
    response = ssl_conn:receive()
    logger.info("Pop3 fetcher USER "..response)
    ssl_conn:send("PASS "..self.password.."\r\n")
    response = ssl_conn:receive()
    logger.info("Pop3 fetcher PASS "..response)
    if not response:match("+OK") then error("Authentication failed: "..response) end

    -- Step 4: List and retrieve messages
    ssl_conn:send("LIST\r\n")
    local msg_count = 0
    while true do
        local line = ssl_conn:receive("*l")
        logger.info("Pop3 fetcher LIST '"..line.."'")

        if line == "." then -- Check for a line containing only a dot, possibly with whitespace
            logger.info("Pop3 fetcher LIST end")
            break
        end
        if line:match("^%d+ %d+$") then -- Check for message number and size format
            msg_count = msg_count + 1
        end
    end
    logger.info("Pop3 fetcher "..msg_count.." messages")
    local progressmsg = InfoMessage:new{
                            text = "Pop3 fetcher "..msg_count.." messages",
                            timeout = 2,
                        }
    UIManager:show(progressmsg,"fast")               
    UIManager:forceRePaint () 

    for msg_id = 1, msg_count do
        logger.info("Pop3 fetcher RETR "..msg_id)
        ssl_conn:send("RETR "..msg_id.."\r\n")

        local temp_email_filepath = os.tmpname() -- Generate a unique temporary filename
        local temp_email_file, err = io.open(temp_email_filepath, "w")
        if not temp_email_file then error("Failed to create temporary email file: "..(err or "unknown error")) end

        -- Read email content line by line and write to temp file
        while true do
            local line = ssl_conn:receive("*l")
            if line == "." then -- Check for a line containing only a dot, possibly with whitespace
                break
            end
            temp_email_file:write(line .. "\r\n")
        end
        temp_email_file:close()

        -- Parse attachments from the temporary file
        self:parse_attachments_from_file(temp_email_filepath)

        -- Delete the temporary email file
        os.remove(temp_email_filepath)

        ssl_conn:send("DELE "..msg_id.."\r\n")
        response = ssl_conn:receive()
        logger.info("Pop3 fetcher DELE "..response) 
    end

    logger.info("Pop3 fetcher QUIT")
    UIManager:show(InfoMessage:new{
        text = "Pop3 fetcher done",
        timeout = 3,
    },"fast")

    -- Cleanup
    ssl_conn:send("QUIT\r\n")
    ssl_conn:close()
end

function Pop3:parse_attachments_from_file(filepath)
    logger.info("Pop3 fetcher parse_attachments_from_file "..filepath)
    local file = io.open(filepath, "r")
    if not file then
        logger.warn("Could not open temporary email file: " .. filepath)
        return
    end

    local progressmsg = nil
    local boundary = nil
    local current_part_headers = {}
    local in_attachment_data = false
    local attachment_filename = nil
    local attachment_encoding = nil
    local output_file = nil
    local last_header_key = nil -- To handle multi-line headers

    logger.info("Pop3 fetcher parse_attachments_from_file looking for boundary ")
    for line in file:lines() do

        if not boundary then
            -- Try to find the boundary in the headers
            local boundary_match = line:lower():match('content%-type: .*;%s*boundary="(.-)"') or line:lower():match('content%-type: .*;%s*boundary=(.-)')
            if boundary_match then
                boundary = "--" .. boundary_match
                logger.info("Found boundary: " .. boundary)
            end
        end

        if boundary and line:match("^" .. boundary ) then -- Start of a new part or end of email
            if output_file then
                output_file:close()
                output_file = nil
                logger.info("Closed attachment file: " .. attachment_filename)
                UIManager:close(progressmsg,"fast")        
                UIManager:forceRePaint ()
            end
            current_part_headers = {}
            in_attachment_data = false
            attachment_filename = nil
            attachment_encoding = nil
            last_header_key = nil -- Reset for new part
        elseif line:match("^%s*$") and not in_attachment_data then -- Empty line, end of headers, start of data
            if current_part_headers["Content-Transfer-Encoding"] and current_part_headers["Content-Disposition"] then
                attachment_encoding = current_part_headers["Content-Transfer-Encoding"]:lower()
                -- Extract filename from potentially multi-line Content-Disposition
                local filename_match = current_part_headers["Content-Disposition"]:match('filename="(.-)"')
                if filename_match then
                    attachment_filename = filename_match
                    in_attachment_data = true
                    local path = self.save_dir .. "/" .. attachment_filename
                    output_file = io.open(path, "wb")
                    if not output_file then
                        logger.warn("Failed to open output file for attachment: " .. path)
                        in_attachment_data = false -- Stop trying to write to this attachment
                    else
                        logger.info("Opened output file for attachment: " .. path)
                        progressmsg=InfoMessage:new{
                            text = "Downloading file : " .. attachment_filename,
                        }
                        UIManager:show(progressmsg,"fast")               
                        UIManager:forceRePaint ()        
                    end
                else
                    logger.info("Pop3 fetcher parse_attachments_from_file no filename in Content-Disposition")

                end
            end
        elseif in_attachment_data and output_file and attachment_encoding:match("base64") then
            -- Decode and write base64 data directly to file
            output_file:write(self:base64_decode(line))
        else
            -- Store headers for the current part, handling multi-line headers
            local header_key_match = line:match("^(.-):")
            if header_key_match then
                last_header_key = header_key_match
                current_part_headers[last_header_key] = line:match(":%s*(.*)")
                logger.info("Pop3 fetcher parse_attachments_from_file header "..header_key_match.." = "..current_part_headers[last_header_key])
            elseif last_header_key and line:match("^%s") then -- Continuation of previous header
                current_part_headers[last_header_key] = current_part_headers[last_header_key] .. " " .. line:match("^%s*(.*)")
                logger.info("Pop3 fetcher parse_attachments_from_file continued header "..last_header_key.." = "..current_part_headers[last_header_key])
            end
        end
    end

    if output_file then
        output_file:close()
        logger.info("Closed final attachment file: " .. attachment_filename)
    end
    file:close()
end

return Pop3
