--local class = require 'ext.class'
--local table = require 'ext.table'
--local tolua = require 'ext.tolua'
--local assert = require 'ext.assert'

local Parser = class()

-- seems redundant. does anyone need to construct a Parser without data? maybe to modify the syntax or something?  just build a subclass in that case?
function Parser:init(data, ...)
	if data then
		assert(self:setData(data, ...))
		--self:setData(data, ...)
	end
end

--[[
returns
	true upon success
	nil, msg, loc upon failure
--]]
function Parser:setData(data, source)
	assert(data, "expected data")
	data = tostring(data)
	self.source = source
	local t = self:buildTokenizer(data)
	t:start()
	self.t = t

	-- default entry point for parsing data sources
	local parseError
	local result = table.pack(xpcall(function()
		self.tree = self:parseTree()
	end, function(err)
		-- throw an object if it's an error parsing the code
		if type(err) == 'table' then
			parseError = err
			return
		else
			return err..'\n'
				..self.t:getpos()..'\n'
				..debug.traceback()
		end
	end))
	
	if not result[1] then
		if not parseError then error(result[2]) end	-- internal error
		return false, self.t:getpos()..': '..parseError.msg 	-- parsed code error
	end
	
	--
	-- now that we have the tree, build parents
	-- ... since I don't do that during construction ...
	self.ast.refreshparents(self.tree)

	if self.t.token then
		return false, self.t:getpos()..": expected eof, found "..self.t.token
	end
	--self.parseExprPrecedenceRulesAndClassNames = nil;--, self.t = false, false
	return true
end

-- TODO I don't need all these, just :getloc()
function Parser:getloc()
	local loc = self.t:getloc()
	loc.source = self.source
	return loc
end

function Parser:canbe(token, tokentype)	-- token is optional
	assert(tokentype)
	if (not token or token == self.t.token)
	and tokentype == self.t.tokentype
	then
		self.lasttoken, self.lasttokentype = self.t.token, self.t.tokentype
		self.t:consume()
		return self.lasttoken, self.lasttokentype
	end
end

function Parser:mustbe(token, tokentype)
	local lasttoken, lasttokentype = self.t.token, self.t.tokentype
	self.lasttoken, self.lasttokentype = self:canbe(token, tokentype)
	if not self.lasttoken and not self.t.r:done() then
		self.t.errors = {msg="expected token="..tolua(token).." tokentype="..tolua(tokentype).." but found token="..tolua(lasttoken).." type="..tolua(lasttokentype)}
		errors(self.t.errors)
	end
	return self.lasttoken, self.lasttokentype
end

-- make new ast node, assign it back to the parser (so it can tell what version / keywords / etc are being used)
function Parser:node(index, ...)
	local node = self.ast[index](...)
	--node.type = index:sub(2,#index)
	node.parser = self
	return node
end

return Parser
