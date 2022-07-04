# run tests located at «lua/tests/» (files named *_spec.lua)
test:
	nvim --headless --noplugin -u ./testing/min_init.vim -c "PlenaryBustedDirectory lua/tests/ { minimal_init = './testing/min_init.vim' }"

