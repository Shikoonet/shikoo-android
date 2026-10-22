package main

const shikooOwnerMethod CoreMethod = "shikooOwner"

type ShikooOwner struct {
	Core   string `json:"core"`
	Server string `json:"server"`
}

var shikooOwners = map[string]func() string{}

// registerShikooOwner, from an owner engine's init(): carrying returns the server it carries now, "" for none (§4).
func registerShikooOwner(core string, carrying func() string) {
	if _, exists := shikooOwners[core]; exists {
		panic("shikoo owner registered twice: " + core)
	}
	shikooOwners[core] = carrying
}

func shikooOwnerNow() ShikooOwner {
	for core, carrying := range shikooOwners {
		if server := carrying(); server != "" {
			return ShikooOwner{Core: core, Server: server}
		}
	}
	return ShikooOwner{}
}

func init() {
	registerMethod(shikooOwnerMethod, withoutArguments(func(response MethodResponse) {
		response.success(shikooOwnerNow())
	}))
}
