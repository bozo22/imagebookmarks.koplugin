local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Const = require("const")

local ImageBookmarksSettings = {}
ImageBookmarksSettings.__index = ImageBookmarksSettings

function ImageBookmarksSettings:new(path, ui)
    local o = {}
    setmetatable(o, self)

    self.settings = LuaSettings:open(path)
    self.ui = ui

    return o
end

function ImageBookmarksSettings:readBookSettings(filename)
    local books = self.settings:readSetting("books")
    if not books then
        return {}
    end

    return books[filename]
end

function ImageBookmarksSettings:readBookSetting(filename, key)
    if not filename then
        return
    end

    local settings = self:readBookSettings(filename)
    if settings then
        return settings[key]
    end
end

function ImageBookmarksSettings:updateBookSetting(filename, config)
    local books = self.settings:readSetting("books", {})
    if not books[filename] then
        books[filename] = {}
    end
    local book_setting = books[filename]
    -- local original_value = { table.unpack(book_setting) }

    for k, v in pairs(config) do
        if k == "_delete" then
            for _, name in ipairs(v) do
                book_setting[name] = nil
            end
        else
            book_setting[k] = v
        end
    end

    self.settings:flush()
    UIManager:broadcastEvent(Event:new("BookSettingsUpdated", { filename = filename, book_setting = book_setting }))
end

function ImageBookmarksSettings:addBookmark(filename, image_filename)
    local books = self.settings:readSetting("books", {})
    if not books[filename] then
        books[filename] = {}
    end
    if not books[filename]["imagebookmarks"] then
        books[filename]["imagebookmarks"] = {}
    end
    local bookmarks = books[filename]["imagebookmarks"]

    local new_entry = {
        image = image_filename,
        center_x_ratio = Const.DEFAULT.CENTER_X_RATIO,
        center_y_ratio = Const.DEFAULT.CENTER_Y_RATIO,
        scale_factor = Const.DEFAULT.SCALE_FACTOR,
        rotation = Const.DEFAULT.ROTATION
    }
    table.insert(bookmarks, new_entry)

    self.settings:flush()
    UIManager:broadcastEvent(Event:new("ImageBookmarksUpdated", { filename = filename }))
end

function ImageBookmarksSettings:updateLocation(doc_path, new_doc_path, copy)
    local books = self.settings:readSetting("books", {})
    if new_doc_path then -- move
        if books[doc_path] then
            if copy then
                books[new_doc_path] = books[doc_path]
            else
                books[new_doc_path] = books[doc_path]
                books[doc_path] = nil
            end
        end
    else -- delete
        books[doc_path] = nil
    end
    self.settings:flush()
end

function ImageBookmarksSettings:removeBookmark(filename, idx, silent, filepath)
    local books = self.settings:readSetting("books", {})
    if not books[filename] or not books[filename]["imagebookmarks"] then
        return
    end

    local bookmarks = books[filename]["imagebookmarks"]
    
    -- Remove entry from table
    table.remove(bookmarks, idx)
    self.settings:flush()

    -- If filepath is given, remove file as well
    if filepath then
        os.remove(filepath)
    end

    if not silent then
        UIManager:broadcastEvent(Event:new("ImageBookmarksUpdated", { filename = filename }))
    end
end

function ImageBookmarksSettings:getBookmarks(filename)
    local books = self.settings:readSetting("books", {})
    if not books[filename] or not books[filename]["imagebookmarks"] then
        return {}
    end

    return books[filename]["imagebookmarks"]
end

function ImageBookmarksSettings:getIdx(filename)
    local books = self.settings:readSetting("books", {})
    if not books[filename] or not books[filename]["idx"] then
        return 1
    end

    return books[filename]["idx"]
end

function ImageBookmarksSettings:setIdx(filename, idx, soft)
    local books = self.settings:readSetting("books", {})
    if not books[filename] then
        books[filename] = {}
    end

    books[filename]["idx"] = idx
    if not soft then
        self.settings:flush()
    end
end

function ImageBookmarksSettings:moveBookmark(filename, idx_from, idx_to)
    local bookmarks = self:getBookmarks(filename)
    if bookmarks[idx_from] and bookmarks[idx_to] then
        local tmp = bookmarks[idx_from]
        table.remove(bookmarks, idx_from)
        table.insert(bookmarks, idx_to, tmp)
        self.settings:flush()
        UIManager:broadcastEvent(Event:new("ImageBookmarksUpdated", { filename = filename }))
        return true
    end
    return false
end

function ImageBookmarksSettings:updateBookmark(filename, idx, soft, center_x_ratio, center_y_ratio, scale_factor, rotation)
    local bookmarks = self:getBookmarks(filename)
    if bookmarks[idx] then
        if self:getRememberPanAndZoom() then
            bookmarks[idx].center_x_ratio = center_x_ratio
            bookmarks[idx].center_y_ratio = center_y_ratio
            bookmarks[idx].scale_factor = scale_factor
        end
        if self:getRememberRotation() then
            bookmarks[idx].rotation = rotation
        end
    end
    self:setIdx(filename, idx, soft)
    if not soft then
        self.settings:flush()
    end
end

function ImageBookmarksSettings:setForAllBooks(vals)
    local books = self.settings:readSetting("books", {})
    if books then
        for filename, _ in pairs(books) do
            local bookmarks = books[filename]["imagebookmarks"]
            if bookmarks then
                for _, bookmark in pairs(bookmarks) do
                    for key, val in pairs(vals) do
                        bookmark[key] = val
                    end
                end
            end
        end
    end
    self:flush()
end

function ImageBookmarksSettings:getRememberRotation()
    return self:readSetting("remember_rotation", true)
end

function ImageBookmarksSettings:setRememberRotation(val)
    self:updateSetting("remember_rotation", val)
    if not val then
        self:setForAllBooks(
            {
                rotation = Const.DEFAULT.ROTATION
            }
        )
    end
end

function ImageBookmarksSettings:toggleRememberRotation()
    local val = self:getRememberRotation()
    self:setRememberRotation(not val)
end

function ImageBookmarksSettings:getRememberPanAndZoom()
    return self:readSetting("remember_pan_and_zoom", true)
end

function ImageBookmarksSettings:setRememberPanAndZoom(val)
    self:updateSetting("remember_pan_and_zoom", val)
    if not val then
        self:setForAllBooks(
            {
                center_x_ratio = Const.DEFAULT.CENTER_X_RATIO,
                center_y_ratio = Const.DEFAULT.CENTER_X_RATIO,
                scale_factor = Const.DEFAULT.SCALE_FACTOR,
            }
        )
    end
end

function ImageBookmarksSettings:getPageTurnButtonMap()
    return self:readSetting("page_turn_button_map", Const.PAGE_TURN_BUTTON_MAP.CYCLE)
end

function ImageBookmarksSettings:setPageTurnButtonMap(val)
    self:updateSetting("page_turn_button_map", val)
end

function ImageBookmarksSettings:toggleRememberPanAndZoom()
    local val = self:getRememberPanAndZoom()
    self:setRememberPanAndZoom(not val)
end

function ImageBookmarksSettings:flush()
    self.settings:flush()
end

function ImageBookmarksSettings:updateSetting(key, value)
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function ImageBookmarksSettings:readSetting(key, default)
    return self.settings:readSetting(key, default)
end


return ImageBookmarksSettings