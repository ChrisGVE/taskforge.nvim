-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
-- event.lua
-- Centralized event manager for custom events and system events.
-- It supports:
--   - Registering custom events and listeners (with pause/resume/off)
--   - Registering a system event handle (e.g., from vim.loop.fs_event) by event name
--   - Unregistering an entire event, which cleans up both the listeners and any system event handle.

local M = {}

-- Internal table to hold custom event listeners.
-- Structure:
--   _events = {
--     ["myplugin:event1"] = { { callback = <function>, paused = false }, ... },
--     ...
--   }
M._events = {}

-- Internal table to hold system event handles.
-- Structure:
--   _system_events = {
--     ["myplugin:event1"] = <uv handle>,
--     ...
--   }
M._system_events = {}

--------------------------------------------------------------------------------
-- Custom Event Registration and Existence Check
--------------------------------------------------------------------------------

--- Register a new custom event.
--- Only registered events may have listeners attached.
--- @param event string: The event name (use a namespace, e.g., "myplugin:event_name").
function M.register(event)
  if M._events[event] then
    vim.notify("Event '" .. event .. "' is already registered.", vim.log.levels.WARN)
    return
  end
  M._events[event] = {}
end

--- Check if a custom event is registered.
--- @param event string: The event name.
--- @return boolean: True if the event exists.
function M.exists(event)
  return M._events[event] ~= nil
end

--------------------------------------------------------------------------------
-- Listener Management for Custom Events
--------------------------------------------------------------------------------

--- Register a listener for a given custom event.
--- The event must be registered first using M.register(event).
---
--- @param event string: The event name.
--- @param callback function: The function to call when the event is emitted.
--- @return table: A handle containing the event name and a reference to the listener.
function M.on(event, callback)
  if not M.exists(event) then
    error(
      "Attempted to register a listener for unregistered event '"
        .. event
        .. "'. Check for typos or register the event first."
    )
  end

  local listener = { callback = callback, paused = false }
  table.insert(M._events[event], listener)
  -- Return a handle so the listener can later be paused, resumed, or removed.
  return { event = event, listener = listener }
end

--- Emit a custom event, calling all active (non-paused) listeners.
--- Additional arguments are passed to the listener callbacks.
---
--- @param event string: The event name.
--- @param ...: Arguments to pass to the callbacks.
function M.emit(event, ...)
  if not M.exists(event) then
    error("Attempted to emit unregistered event '" .. event .. "'.")
  end

  for _, listener in ipairs(M._events[event]) do
    if not listener.paused then
      listener.callback(...)
    end
  end
end

--- Remove (de-register) a listener using its handle.
---
--- @param handle table: The handle returned by M.on().
--- @return boolean: True if removal succeeded.
function M.off(handle)
  local event = handle.event
  if not M.exists(event) then
    error("Attempted to remove a listener from unregistered event '" .. event .. "'.")
  end

  for i, listener in ipairs(M._events[event]) do
    if listener == handle.listener then
      table.remove(M._events[event], i)
      return true
    end
  end
  return false
end

--- Pause a listener so it no longer reacts to emitted events.
--- @param handle table: The handle returned by M.on().
function M.pause(handle)
  if handle and handle.listener then
    handle.listener.paused = true
  end
end

--- Resume a previously paused listener.
--- @param handle table: The handle returned by M.on().
function M.resume(handle)
  if handle and handle.listener then
    handle.listener.paused = false
  end
end

--------------------------------------------------------------------------------
-- System Event (uv handle) Management
--------------------------------------------------------------------------------

--- Register a system event handle (for example, one returned by uv.new_fs_event)
--- and associate it with a custom event name. This lets you later retrieve or clean
--- up the system handle.
---
--- If the custom event is not already registered, it will be registered.
---
--- @param event string: The event name.
--- @param uv_handle userdata: The uv handle (e.g., from vim.loop.new_fs_event()).
function M.register_system_event(event, uv_handle)
  if not M.exists(event) then
    -- Optionally, auto-register the event if it isn't already registered.
    M.register(event)
  end
  M._system_events[event] = uv_handle
end

--- Retrieve a registered system event handle by event name.
--- @param event string: The event name.
--- @return userdata: The uv handle, or nil if not registered.
function M.get_system_event(event)
  return M._system_events[event]
end

--- Unregister a system event.
--- This stops and closes the uv handle, then removes it from the table.
--- @param event string: The event name.
function M.unregister_system_event(event)
  local handle = M._system_events[event]
  if handle then
    -- Stop and close the uv handle if it supports these methods.
    if handle.stop then
      handle:stop()
    end
    if handle.close then
      handle:close()
    end
    M._system_events[event] = nil
  end
end

--------------------------------------------------------------------------------
-- Unregistering an Entire Event (Custom and System)
--------------------------------------------------------------------------------

--- Unregister an entire event.
--- This function removes all custom listeners for the event and, if a system event
--- handle is registered with this event, it unregisters that as well.
---
--- @param event string: The event name.
function M.unregister_event(event)
  if not M.exists(event) then
    vim.notify("Cannot unregister non-existing event: " .. event, vim.log.levels.WARN)
    return
  end

  -- Remove all custom listeners by setting the table to nil.
  M._events[event] = nil

  -- Unregister the associated system event, if any.
  if M._system_events[event] then
    M.unregister_system_event(event)
  end
end

--------------------------------------------------------------------------------
-- (Optional) Debug Utility: List Registered Custom Events and Their Listener Count
--------------------------------------------------------------------------------

--- Return a table of registered custom events and the number of listeners for each.
function M.list_events()
  local events = {}
  for event, listeners in pairs(M._events) do
    events[event] = #listeners
  end
  return events
end

--------------------------------------------------------------------------------
-- Module Return
--------------------------------------------------------------------------------

return M
