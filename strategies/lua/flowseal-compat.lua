-- Derived from bol-van/zapret2 v1.0.7 zapret-antidpi.lua. Flowseal altorder=1.
function flowseal_hostfakesplit_alt1(ctx, desync)
	if not desync.dis.tcp then
		-- do not cutoff on related icmp
		if not desync.dis.icmp then instance_cutoff_shim(ctx, desync) end
		return
	end
	direction_cutoff_opposite(ctx, desync)
	if desync.arg.optional and desync.arg.blob and not blob_exist(desync, desync.arg.blob) then
		DLOG("hostfakesplit: blob '"..desync.arg.blob.."' not found. skipped")
		return
	end
	local data = blob_or_def(desync, desync.arg.blob) or desync.reasm_data or desync.dis.payload
	if #data>0 and direction_check(desync) and payload_check(desync) then
		if replay_first(desync) then
			local pos = resolve_range(data, desync.l7payload, "host,endhost-1", true)
			if pos then
				if b_debug then DLOG("hostfakesplit: resolved host range: "..table.concat(zero_based_pos(pos)," ")) end

				-- do not apply fooling to original parts except tcp_ts_up but apply ip_id
				local part, fakehost
				local opts_orig = {rawsend = rawsend_opts_base(desync), reconstruct = {}, ipfrag = {}, ipid = desync.arg, fooling = {tcp_ts_up = desync.arg.tcp_ts_up}}
				local opts_fake = {rawsend = rawsend_opts(desync), reconstruct = reconstruct_opts(desync), ipfrag = {}, ipid = desync.arg, fooling = desync.arg}

				part = string.sub(data,1,pos[1]-1)
				if b_debug then DLOG("hostfakesplit: sending before_host part 0-"..(pos[1]-2).." len="..#part.." : "..hexdump_dlog(part)) end
				if not rawsend_payload_segmented(desync,part,0, opts_orig) then return VERDICT_PASS end

				fakehost = genhost(pos[2]-pos[1]+1, desync.arg.host)

				if not desync.arg.nofake1 then
					if b_debug then DLOG("hostfakesplit: sending fake host part (1) "..(pos[1]-1).."-"..(pos[2]-1).." len="..#fakehost.." : "..hexdump_dlog(fakehost)) end
					if not rawsend_payload_segmented(desync,fakehost,pos[1]-1, opts_fake) then return VERDICT_PASS end
				end

				part = string.sub(data,pos[2]+1)
				if not rawsend_payload_segmented(desync,part,pos[2], opts_orig) then return VERDICT_PASS end
				local midhost
				if desync.arg.midhost then
					midhost = resolve_pos(data,desync.l7payload,desync.arg.midhost)
					if midhost then
						DLOG("hosfakesplit: midhost marker resolved to "..midhost)
						if midhost<=pos[1] or midhost>pos[2] then
							DLOG("hostfakesplit: midhost is not inside the host range")
							midhost = nil
						end
					else
						DLOG("hostfakesplit: cannot resolve midhost marker '"..desync.arg.midhost.."'")
					end
				end
				-- if present apply ipfrag only to real host parts. fakes and parts outside of the host must be visible to DPI.
				if midhost then
					part = string.sub(data,pos[1],midhost-1)
					if b_debug then DLOG("hostfakesplit: sending real host part 1 "..(pos[1]-1).."-"..(midhost-2).." len="..#part.." : "..hexdump_dlog(part)) end
					if not rawsend_payload_segmented(desync,part,pos[1]-1, opts_orig) then return VERDICT_PASS	end

					part = string.sub(data,midhost,pos[2])
					if b_debug then DLOG("hostfakesplit: sending real host part 2 "..(midhost-1).."-"..(pos[2]-1).." len="..#part.." : "..hexdump_dlog(part)) end
					if not rawsend_payload_segmented(desync,part,midhost-1, opts_orig) then return VERDICT_PASS end
				else
					part = string.sub(data,pos[1],pos[2])
					if b_debug then DLOG("hostfakesplit: sending real host part "..(pos[1]-1).."-"..(pos[2]-1).." len="..#part.." : "..hexdump_dlog(part)) end
					if not rawsend_payload_segmented(desync,part,pos[1]-1, opts_orig) then return VERDICT_PASS	end
				end

				replay_drop_set(desync)
				return desync.arg.nodrop and VERDICT_PASS or VERDICT_DROP
			else
				DLOG("hostfakesplit: host range cannot be resolved")
			end
		else
			DLOG("hostfakesplit: not acting on further replay pieces")
		end
		-- drop replayed packets if reasm was sent successfully in splitted form
		if replay_drop(desync) then
			return desync.arg.nodrop and VERDICT_PASS or VERDICT_DROP
		end
	end
end

