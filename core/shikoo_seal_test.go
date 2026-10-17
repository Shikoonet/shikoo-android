package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"math/big"
	"testing"
)

// RFC 8032 section 7.1, TESTS 1 to 3: public key, message, signature.
var rfc8032 = []struct{ key, message, sig string }{
	{
		"d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
		"",
		"e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
	},
	{
		"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
		"72",
		"92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
	},
	{
		"fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
		"af82",
		"6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
	},
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func b64(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

func flipped(b []byte, at int) []byte {
	c := append([]byte(nil), b...)
	c[at] ^= 1
	return c
}

func TestCheckSealIsDispatchable(t *testing.T) {
	if _, ok := methodHandlers[checkSealMethod]; !ok {
		t.Fatal("checkSeal answers not_implemented")
	}
}

func TestCheckSealAcceptsRFC8032AndNoMutation(t *testing.T) {
	for i, v := range rfc8032 {
		key, message, sig := unhex(t, v.key), unhex(t, v.message), unhex(t, v.sig)
		if !checkSeal(&CheckSealParams{Key: b64(key), Message: string(message), Sig: b64(sig)}) {
			t.Fatalf("TEST %d: refused", i+1)
		}
		for _, at := range []int{0, 31, 32, 63} {
			if checkSeal(&CheckSealParams{Key: b64(key), Message: string(message), Sig: b64(flipped(sig, at))}) {
				t.Fatalf("TEST %d: signature byte %d flipped, still accepted", i+1, at)
			}
		}
		for _, at := range []int{0, 31} {
			if checkSeal(&CheckSealParams{Key: b64(flipped(key, at)), Message: string(message), Sig: b64(sig)}) {
				t.Fatalf("TEST %d: key byte %d flipped, still accepted", i+1, at)
			}
		}
		if checkSeal(&CheckSealParams{Key: b64(key), Message: string(message) + "x", Sig: b64(sig)}) {
			t.Fatalf("TEST %d: longer message accepted", i+1)
		}
		if len(message) > 0 && checkSeal(&CheckSealParams{Key: b64(key), Message: string(flipped(message, 0)), Sig: b64(sig)}) {
			t.Fatalf("TEST %d: changed message accepted", i+1)
		}
	}
}

// S and S+L are the same scalar; RFC 8032 5.1.7 rejects the second, so a seal has one encoding.
func TestCheckSealRefusesANonCanonicalS(t *testing.T) {
	v := rfc8032[0]
	sig := unhex(t, v.sig)
	order, _ := new(big.Int).SetString("7237005577332262213973186563042994240857116359379907606001950938285454250989", 10)
	le := func(b []byte) *big.Int {
		r := make([]byte, len(b))
		for i := range b {
			r[len(b)-1-i] = b[i]
		}
		return new(big.Int).SetBytes(r)
	}
	s := new(big.Int).Add(le(sig[32:]), order)
	be := s.FillBytes(make([]byte, 32))
	for i := 0; i < 32; i++ {
		sig[32+i] = be[31-i]
	}
	if checkSeal(&CheckSealParams{Key: b64(unhex(t, v.key)), Message: "", Sig: b64(sig)}) {
		t.Fatal("S+L accepted")
	}
}

func TestCheckSealRefusesBrokenInput(t *testing.T) {
	v := rfc8032[1]
	key, sig := unhex(t, v.key), unhex(t, v.sig)
	for name, params := range map[string]CheckSealParams{
		"no key":        {Key: "", Message: "r", Sig: b64(sig)},
		"short key":     {Key: b64(key[:31]), Message: "r", Sig: b64(sig)},
		"long key":      {Key: b64(append(key, 0)), Message: "r", Sig: b64(sig)},
		"key not b64":   {Key: "@" + b64(key)[1:], Message: "r", Sig: b64(sig)},
		"no sig":        {Key: b64(key), Message: "r", Sig: ""},
		"short sig":     {Key: b64(key), Message: "r", Sig: b64(sig[:63])},
		"hex sig":       {Key: b64(key), Message: "r", Sig: v.sig},
		"trailing junk": {Key: b64(key), Message: "r", Sig: base64.URLEncoding.EncodeToString(sig) + "-"},
		"another's key": {Key: b64(unhex(t, rfc8032[0].key)), Message: "r", Sig: b64(sig)},
	} {
		if checkSeal(&params) {
			t.Fatalf("%s: accepted", name)
		}
	}
}

// The Windows updater's message, `<version_code>:<sha256>`: the seal of one build never fits another number.
func TestCheckSealBindsTheBuildNumber(t *testing.T) {
	private := ed25519.NewKeyFromSeed(make([]byte, ed25519.SeedSize))
	key := b64(private.Public().(ed25519.PublicKey))
	sha := "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
	sig := b64(ed25519.Sign(private, []byte("57:"+sha)))
	if !checkSeal(&CheckSealParams{Key: key, Message: "57:" + sha, Sig: sig}) {
		t.Fatal("refused its own seal")
	}
	for _, other := range []string{"58:" + sha, "570:" + sha, "57:" + sha[:63] + "9", "57:" + sha + "\n"} {
		if checkSeal(&CheckSealParams{Key: key, Message: other, Sig: sig}) {
			t.Fatalf("%q accepted the seal of 57", other)
		}
	}
}
