package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"sync"
	"testing"
)

const sealSha = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

const sealMessage = "shikoonet-windows-update:57:" + sealSha

// `openssl dgst -sha256 -sign` over sealMessage, as CI makes a seal, with a throwaway 2048-bit key already deleted.
const (
	opensslKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAob8KQSm6BJpcdolJomCrH9SIWm2ciDlF64eWklrfScrMz0r/H+XbZ75IBCjQyz8vgi1BZ3XIJfs2C5rFWvlk/Evv4iET5TSErff1U0qHlJZlDL3fbPTiR7kTw+slMgJ4W/0VG73OeUV+rpgxaFHNoDDoa6jAvS2gxOdES5a/JidyhO9qIDyU6U8iqzHoqJWyWq8IcSs6ZgCjHeYXxQzWz0pj9dkAKo2/Dqn0clFnBDjzkonvLvVlutcg5sqQcnBZmXDbi8aMKci7gEMKHbElH+Mk7ykSfV6BQyo5L/nj9dG3zrOht6dsWgbQpA1Ke/OH5Ctqko83pZmytOfiWJk9owIDAQAB"
	opensslSig = "D4MZI8vljBZFBUXEvgKqlFMlu3ruOnYEdXuOJtyx+zzDUTYHQq0JcLh2lqVufO/PV8ZtRRWJEdWMUGcUi2wzi0ei5TliO6LbXpBrxDHsSSiflVV3u8yHjjcIbh5lguCIvY8P9SmGp7kVR+w+Tb8wCCOoGXZ/nF51mkOPA5wZ5PVhejHIfGZY7G1TqBeJE0FI6ZdC8+mh2WrDYHSK0ynVcLL2EfLaKvpgg1vuR61Yqmuf+lTP1sgC/UhGtSkesvu13Y3bD6cd7/QDlJjoasA1MTsRkmS295ov5tSAYGp0B8oDTrfn3SlDv+bp8SHJEs0z0I9Dhhw2M5tzUTJu5KpejA=="
)

var sealKeys = sync.OnceValues(func() (*rsa.PrivateKey, *rsa.PrivateKey) {
	return mustRSA(2048), mustRSA(4096)
})

func mustRSA(bits int) *rsa.PrivateKey {
	key, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		panic(err)
	}
	return key
}

func b64(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

func spki(t *testing.T, public any) string {
	t.Helper()
	der, err := x509.MarshalPKIXPublicKey(public)
	if err != nil {
		t.Fatal(err)
	}
	return b64(der)
}

func seal(t *testing.T, key *rsa.PrivateKey, message string) []byte {
	t.Helper()
	digest := sha256.Sum256([]byte(message))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return sig
}

func TestCheckSealIsDispatchable(t *testing.T) {
	if _, ok := methodHandlers[checkSealMethod]; !ok {
		t.Fatal("checkSeal answers not_implemented")
	}
}

func TestCheckSealAcceptsWhatOpensslSigns(t *testing.T) {
	if !checkSeal(&CheckSealParams{Key: opensslKey, Message: sealMessage, Sig: opensslSig}) {
		t.Fatal("refused openssl's seal")
	}
}

func TestCheckSealTakesOnlyItsOwnKey(t *testing.T) {
	staging, production := sealKeys()
	for _, c := range []struct {
		name         string
		signer, pins *rsa.PrivateKey
		want         bool
	}{
		{"staging on staging", staging, staging, true},
		{"production on production", production, production, true},
		{"production's seal on a staging build", production, staging, false},
		{"staging's seal on a production build", staging, production, false},
	} {
		got := checkSeal(&CheckSealParams{Key: spki(t, &c.pins.PublicKey), Message: sealMessage, Sig: b64(seal(t, c.signer, sealMessage))})
		if got != c.want {
			t.Fatalf("%s: got %v", c.name, got)
		}
	}
}

func TestCheckSealBindsNumberChecksumAndPrefix(t *testing.T) {
	staging, _ := sealKeys()
	key, sig := spki(t, &staging.PublicKey), b64(seal(t, staging, sealMessage))
	for _, other := range []string{
		"shikoonet-windows-update:58:" + sealSha,
		"shikoonet-windows-update:570:" + sealSha,
		"shikoonet-windows-update:57:" + sealSha[:63] + "9",
		"shikoonet-windows-update:57:" + sealSha + "\n",
		"57:" + sealSha,
		"shikoonet-android-update:57:" + sealSha,
	} {
		if checkSeal(&CheckSealParams{Key: key, Message: other, Sig: sig}) {
			t.Fatalf("%q accepted the seal of %q", other, sealMessage)
		}
	}
}

func TestCheckSealRefusesABrokenSeal(t *testing.T) {
	staging, _ := sealKeys()
	key, raw := spki(t, &staging.PublicKey), seal(t, staging, sealMessage)
	flip := func(at int) []byte {
		c := append([]byte(nil), raw...)
		c[at] ^= 1
		return c
	}
	for name, sig := range map[string]string{
		"first byte flipped": b64(flip(0)),
		"last byte flipped":  b64(flip(len(raw) - 1)),
		"one byte short":     b64(raw[1:]),
		"one byte long":      b64(append([]byte{0}, raw...)),
		"empty":              "",
		"hex, not base64":    hex.EncodeToString(raw),
		"url-safe base64":    base64.RawURLEncoding.EncodeToString(raw) + "-_",
	} {
		if checkSeal(&CheckSealParams{Key: key, Message: sealMessage, Sig: sig}) {
			t.Fatalf("%s: accepted", name)
		}
	}
}

func TestCheckSealRefusesAnotherScheme(t *testing.T) {
	staging, _ := sealKeys()
	key := spki(t, &staging.PublicKey)
	digest := sha256.Sum256([]byte(sealMessage))
	pss, err := rsa.SignPSS(rand.Reader, staging, crypto.SHA256, digest[:], nil)
	if err != nil {
		t.Fatal(err)
	}
	sha1Digest := sha1.Sum([]byte(sealMessage))
	overSha1, err := rsa.SignPKCS1v15(rand.Reader, staging, crypto.SHA1, sha1Digest[:])
	if err != nil {
		t.Fatal(err)
	}
	for name, sig := range map[string][]byte{"PSS": pss, "PKCS#1 v1.5 over SHA-1": overSha1} {
		if checkSeal(&CheckSealParams{Key: key, Message: sealMessage, Sig: b64(sig)}) {
			t.Fatalf("%s: accepted", name)
		}
	}
}

func TestCheckSealRefusesAKeyThatIsNotRSA2048(t *testing.T) {
	weak := mustRSA(1024)
	digest := sha256.Sum256([]byte(sealMessage))
	weakSig, err := rsa.SignPKCS1v15(rand.Reader, weak, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	edPublic, edPrivate, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ec, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ecSig, err := ecdsa.SignASN1(rand.Reader, ec, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	opensslDer, _ := base64.StdEncoding.DecodeString(opensslKey)
	for name, c := range map[string]CheckSealParams{
		"RSA 1024":       {Key: spki(t, &weak.PublicKey), Sig: b64(weakSig)},
		"Ed25519":        {Key: spki(t, edPublic), Sig: b64(ed25519.Sign(edPrivate, []byte(sealMessage)))},
		"ECDSA P-256":    {Key: spki(t, &ec.PublicKey), Sig: b64(ecSig)},
		"no key":         {Key: "", Sig: opensslSig},
		"key not base64": {Key: "@" + opensslKey[1:], Sig: opensslSig},
		"key cut short":  {Key: b64(opensslDer[:len(opensslDer)-1]), Sig: opensslSig},
	} {
		c.Message = sealMessage
		if checkSeal(&c) {
			t.Fatalf("%s: accepted", name)
		}
	}
}
