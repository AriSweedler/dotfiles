return {
	s({
		trig = "gotest",
		desc = "Create a new t.Run block in a go test",
	}, {
		t('t.Run("'),
		i(1, "test_name"),
		t('", func(t *testing.T) {'),
		t({ "", "\t" }),
		i(0),
		t({ "", "})" }),
	}),
}
