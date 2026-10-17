package main

import (
	"crypto/ed25519"
	"encoding/base64"
)

// checkSeal is Go's crypto/ed25519 for the Windows updater; Dart has no Ed25519 of its own.
const checkSealMethod CoreMethod = "checkSeal"

type CheckSealParams struct {
	Key     string `json:"key"`
	Message string `json:"message"`
	Sig     string `json:"sig"`
}

func init() {
	registerMethod(checkSealMethod, withArguments(func(params *CheckSealParams, response MethodResponse) {
		response.success(checkSeal(params))
	}))
}

func checkSeal(params *CheckSealParams) bool {
	key, err := base64.StdEncoding.DecodeString(params.Key)
	if err != nil || len(key) != ed25519.PublicKeySize {
		return false
	}
	sig, err := base64.StdEncoding.DecodeString(params.Sig)
	if err != nil || len(sig) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(key, []byte(params.Message), sig)
}
