local Process = {}

function Process.new(opts)
  assert(
    type(opts) == 'table' and type(opts.cmd) == 'string' and #opts.cmd > 0,
    'opts.cmd must be a string'
  )
  opts = opts or {}
  local self = {
    cmd = opts.cmd,
    args = opts.args or {},
    out_pipe = vim.loop.new_pipe(false),
    err_pipe = vim.loop.new_pipe(false),
    out_list = {},
    err_list = {},
    handle = nil,
    pid = nil,
    has_spawn_error = false,
    use_main_loop = opts.use_main_loop or true,
    verbose = opts.verbose,
  }
  return setmetatable(self, {__index = Process})
end

function Process:run(cb)
  assert(type(cb) == 'function' or type(cb) == 'nil', 'cb must be a function or a nil')
  self.handle, self.pid = vim.loop.spawn(self.cmd, {
    args = self.args,
    stdio = {nil, self.out_pipe, self.err_pipe},
  }, function(code, signal)
    self:_on_finished(cb, code, signal)
  end)
  self:log(('start: pid -> %d'):format(self.pid))
  vim.loop.read_start(self.out_pipe, self:_on_read(self.out_list))
  vim.loop.read_start(self.err_pipe, self:_on_read(self.err_list))
end

function Process:_on_read(list)
  return function(err, data)
    if err then
      self:error(err)
      self.has_spawn_error = true
    elseif data then
      table.insert(list, data)
    end
  end
end

function Process:_on_finished(cb, code, signal)
  self:log(('finish: code -> %d, signal -> %d'):format(code, signal))
  self.out_pipe:read_stop()
  self.err_pipe:read_stop()
  self.out_pipe:close()
  self.err_pipe:close()
  if self.has_spawn_error or not cb then
    return
  end
  local result = {
    code = code,
    signal = signal,
    out = table.concat(self.out_list),
    err = table.concat(self.err_list),
  }
  if self.use_main_loop then
    vim.schedule(function()
      cb(result)
    end)
  else
    cb(result)
  end
end

function Process:log(msg, hi)
  if self.verbose or hi == 'ErrorMsg' then
    vim.schedule(function()
      vim.api.nvim_echo({
        {('[hop.Process]: %s'):format(msg), hi or 'Normal'}
      }, true, {})
    end)
  end
end

function Process:error(msg)
  self:log(msg, 'ErrorMsg')
end

return Process
