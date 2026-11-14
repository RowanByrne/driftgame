--!nonstrict
return function(className, properties, parent)
	local object = Instance.new(className)
	for name, value in properties or {} do object[name] = value end
	object.Parent = parent
	return object
end
