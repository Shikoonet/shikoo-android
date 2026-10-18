package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"testing"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/structure"
)

func TestRealityOffersX25519MLKEM768UnlessTheSubscriptionSaysFalse(t *testing.T) {
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	publicKey := base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes())
	decoder := structure.NewDecoder(structure.Option{TagName: "proxy", WeaklyTypedInput: true, KeyReplacer: structure.DefaultKeyReplacer})

	for _, tc := range []struct {
		name   string
		option map[string]any
		want   bool
	}{
		{"unset", map[string]any{}, true},
		{"false", map[string]any{"support-x25519mlkem768": false}, false},
		{"true", map[string]any{"support-x25519mlkem768": true}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.option["public-key"] = publicKey
			var options outbound.RealityOptions
			if err := decoder.Decode(tc.option, &options); err != nil {
				t.Fatal(err)
			}
			config, err := options.Parse()
			if err != nil {
				t.Fatal(err)
			}
			if config.SupportX25519MLKEM768 != tc.want {
				t.Fatalf("X25519MLKEM768 offered: %v, want %v", config.SupportX25519MLKEM768, tc.want)
			}
		})
	}
}
