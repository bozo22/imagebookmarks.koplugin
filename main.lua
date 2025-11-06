local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ImageViewer = require("ui/widget/imageviewer")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local ImageBookmarkViewer = require("imagebookmarkviewer")
local ImageBookmarksSettings = require("imagebookmarks_settings")
local DocSettings = require("docsettings")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local Device = require("device")
local Const = require("const")
local ffiutil = require("ffi/util")
local patches = require("patches")

local ImageBookmarks = WidgetContainer:extend {
    name = "imagebookmarks",
    is_doc_only = false,
    enabled = true,
    settings = nil
}

function ImageBookmarks:onDispatcherRegisterActions()
    Dispatcher:registerAction("open_image_bookmark_viewer_action",
        { category = "none", event = "OpenImageBookmarkViewer", title = _("Open image bookmark viewer"), general = true, })
end

OriginalInit = ImageViewer.init

function ImageBookmarks:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.doc_path = self.ui and self.ui.document and self.ui.document.file

    self.settings = ImageBookmarksSettings:new(
        ("%s/%s"):format(DataStorage:getSettingsDir(), "imagebookmarks_settings.lua"),
        self.ui
    )

    if self.doc_path then
        -- Get the document's bookmark folder and load images
        self.bookmark_dir = DocSettings:getSidecarDir(self.doc_path) .. "/imagebookmarks"
        util.makePath(self.bookmark_dir)
        self:addNewImages()
        self:reloadImages()

        -- Add bookmark button to imageviewer 
        patches.ImageViewer_patch()
    else
        -- Remove bookmark button from imageviewer 
        patches.ImageViewer_undo_patch()
    end
end

function ImageBookmarks:onLocationUpdated(doc_path, new_doc_path, copy)
    local sidecar_dir = DocSettings:getSidecarDir(doc_path)
    local bookmark_dir = sidecar_dir .. "/imagebookmarks"
    local new_bookmark_dir = DocSettings:getSidecarDir(new_doc_path) .. "/imagebookmarks"
    local do_purge

    if new_doc_path then                                                            
        if G_reader_settings:readSetting("document_metadata_folder") ~= "hash" then 
            local new_sidecar_dir
            if not new_sidecar_dir then
                new_sidecar_dir = DocSettings:getSidecarDir(new_doc_path)
                util.makePath(new_sidecar_dir)
                util.makePath(new_bookmark_dir)
            end

            for file in lfs.dir(bookmark_dir) do
                if file ~= "." and file ~= ".." then
                    ffiutil.copyFile(bookmark_dir .. "/" .. file, new_bookmark_dir .. "/" .. file)
                end
            end
            do_purge = not copy
        end
    else -- delete
        do_purge = true
    end

    self.settings:updateLocation(doc_path, new_doc_path, copy)

    if do_purge then
        ffiutil.purgeDir(bookmark_dir)
        DocSettings.removeSidecarDir(sidecar_dir)
    end
end

function ImageBookmarks:addToMainMenu(menu_items)
    menu_items.imagebookmarks = {
        text = _("Image bookmarks"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Remember rotation"),
                checked_func = function()
                    return self.settings:getRememberRotation()
                end,
                callback = function()
                    self.settings:toggleRememberRotation()
                end,
            },
            {
                text = _("Remember pan and zoom"),
                checked_func = function()
                    return self.settings:getRememberPanAndZoom()
                end,
                callback = function()
                    self.settings:toggleRememberPanAndZoom()
                end,
            },
            {
                text = _("About Image Bookmarks"),
                keep_menu_open = true,
                callback = function()
                    local const = require("const")
                    UIManager:show(InfoMessage:new({
                        text = "Image Bookmarks plugin for KOReader\n\nVersion: "
                        .. const.VERSION
                        .. "\n\nSee https://github.com/bozo22/imagebookmarks.koplugin.",
                    }))
                end,
            },
        },
    }

    if Device:hasKeys() then
        local physical_button_settings = {
            text = _("Page turn button map"),
            sub_item_table = {
                {
                    text = _("Cycle"),
                    checked_func = function()
                        return self.settings:getPageTurnButtonMap() == Const.PAGE_TURN_BUTTON_MAP.CYCLE
                    end,
                    callback = function()
                        self.settings:setPageTurnButtonMap(Const.PAGE_TURN_BUTTON_MAP.CYCLE)
                    end
                },
                {
                    text = _("Zoom"),
                    checked_func = function()
                        return self.settings:getPageTurnButtonMap() == Const.PAGE_TURN_BUTTON_MAP.ZOOM
                    end,
                    callback = function()
                        self.settings:setPageTurnButtonMap(Const.PAGE_TURN_BUTTON_MAP.ZOOM)
                    end
                },
                {
                    text = _("Close / Menu"),
                    checked_func = function()
                        return self.settings:getPageTurnButtonMap() == Const.PAGE_TURN_BUTTON_MAP.CLOSE_MENU
                    end,
                    callback = function()
                        self.settings:setPageTurnButtonMap(Const.PAGE_TURN_BUTTON_MAP.CLOSE_MENU)
                    end
                }
            }
        }
        table.insert(menu_items.imagebookmarks.sub_item_table, 3, physical_button_settings)
    end
end

function ImageBookmarks:reloadImages()
    self.image_datas = {}

    -- Iterate through saved bookmarks and try to load them
    local bookmarks_list = self.settings:getBookmarks(self.doc_path)
    for idx, bookmark in ipairs(bookmarks_list) do
        local image_path = self.bookmark_dir .. "/" .. bookmark.image
        local file = io.open(image_path, "rb")
        if file then
            local data = file:read("*a")
            file:close()
            table.insert(self.image_datas, data)                               -- Image loaded successfully -> cache it
        else
            self.settings:removeBookmark(self.doc_path, idx, true, image_path) -- Can't load image -> delete bookmark
        end
    end
    UIManager:broadcastEvent(Event:new("ImagesReloaded", {}))
end

function ImageBookmarks:onImageBookmarksUpdated(data)
    if data.filename == self.doc_path then
        self:reloadImages()
    end
end

function ImageBookmarks:addNewImages()
    local bookmarks_list = self.settings:getBookmarks(self.doc_path)

    for file in lfs.dir(self.bookmark_dir) do
        if file ~= "." and file ~= ".." then
            local exists = false
            for _, entry in pairs(bookmarks_list) do
                if entry.image == file then
                    exists = true
                    break
                end
            end

            if not exists then
                -- New image found, add to bookmarks
                self.settings:addBookmark(self.doc_path, file)
            end
        end
    end
end

function ImageBookmarks:onImageBookmarkAdd(image)
    if image and self.doc_path and self.bookmark_dir then
        -- Generate a unique filename for the image
        local image_filename = "imagebookmark_" .. os.time() .. ".png"
        local image_filepath = self.bookmark_dir .. "/" .. image_filename

        -- Save the BlitBuffer image to file
        util.makePath(self.bookmark_dir)
        image:writePNG(image_filepath)

        -- Store the image path in bookmarks
        self.settings:addBookmark(self.doc_path, image_filename)
        UIManager:show(InfoMessage:new { text = _("Image bookmarked!") })
    end
end

function ImageBookmarks:onOpenImageBookmarkViewer()
    if not self.doc_path or not self.bookmark_dir then
        UIManager:show(InfoMessage:new { text = _("No book open!") })
        return
    end

    if #self.settings:getBookmarks(self.doc_path) < 1 then
        UIManager:show(InfoMessage:new { text = _("No images bookmarked!") })
        return
    end

    local imagebookmarkviewer = ImageBookmarkViewer:new {
        image_bookmarks = self,
        doc_path = self.doc_path,
        settings = self.settings,
        image_disposable = false,
        with_title_bar = false,
        fullscreen = true,
    }

    UIManager:show(imagebookmarkviewer)
end

return ImageBookmarks
