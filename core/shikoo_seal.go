package main

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
)

// checkSeal is RSA PKCS#1 v1.5 over SHA-256 for the Windows updater, against an Android signing key's public half.
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
	der, err := base64.StdEncoding.DecodeString(params.Key)
	if err != nil {
		return false
	}
	parsed, err := x509.ParsePKIXPublicKey(der)
	key, ok := parsed.(*rsa.PublicKey)
	if err != nil || !ok || key.N.BitLen() < 2048 {
		return false
	}
	sig, err := base64.StdEncoding.DecodeString(params.Sig)
	if err != nil {
		return false
	}
	digest := sha256.Sum256([]byte(params.Message))
	return rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig) == nil
}
