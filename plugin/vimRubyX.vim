ruby << EORUBY
module VIM
	Restricted = { :singleton_method_added=>true, :marshall_array=>true, :method_missing=>true, :get_args=>true, :gets=>true, :puts=>true, '<<'.intern=>true, :marshal=>true}
	class << self
		def marshal(input)
			input.gsub!(/"/, '\"')
			input.gsub!(/\\/, '\\')
			return input
		end

		def <<(input)
			command('let ruby_saved_register = @y')      #save register
			#simple escapes for now
			input = marshal(input)
			command(%[let @y="#{input}"])
			command(":silent @y")         #send it to vim
			command("let @y=ruby_saved_register")   #restore register
		end

		def gets(input)
			evaluate("input('#{input}')")
		end

        def puts(*inputs)
            inputs.each { |input|  command("echo '#{input.to_s}'")} 
		end

		def get_args(arity, vararg)
			args = []
			for i in 1..arity
				args.push evaluate('a:a' + i.to_s )
			end
			if vararg
				varargs = []
				varity = evaluate('a:0').to_i
				for i in 1..varity
					varargs.push(evaluate('a:' + i.to_s))
				end
				args.push(varargs) if varity > 0
			end
			return args
		end

		def marshall_array(argv)
			if argv.length == 0
				return ''
			else
				argv = argv.collect {|elem| marshal(elem)}
				return %["#{argv.join(%q[","])}"]
			end
		end

		def method_missing(id, *argv)
			puts %q(method missing ) + id.to_s if (defined?($vimRubyDebug) && $vimRubyDebug)
			VIM::Restricted[id] = true
			#puts "VIM::Restricted #{VIM::Restricted.inspect}"
			#evaluate('input("waiting")')
			methodName = id.id2name
			raise NameError, %Q(can't find method #{methodName}) unless VIM::evaluate(%Q[exists('*#{methodName}')])
			deffunc = <<-EOEVAL
			def VIM.#{methodName}(*argv)
				VIM.evaluate(%Q(#{methodName}(#{marshall_array(argv)})))
			end
			EOEVAL
			eval deffunc
			puts "method added " + id.to_s + " as " + deffunc if (defined?($vimRubyDebug) && $vimRubyDebug)
			send(methodName, *argv)
		end

		def singleton_method_added(id)
			#we need to build our new vim function in a string then put it in a register then eval the register
			#puts "VIM::Restricted #{VIM::Restricted.inspect}"
			if VIM::Restricted[id]
				return 
			end
			methodName = id.id2name
			arity = method(id).arity
			vararg = false
			if arity < 0
				arity = -arity-1
				vararg = true
			end
			args = []
			for i in 1..arity
				args.push 'a' + i.to_s
			end
			if vararg
				args.push '...'
			end
			args = args.join(',')

			puts "adding function #{methodName}(#{args}) in vim" if (defined?($vimRubyDebug) && $vimRubyDebug)
			if arity == 0
				vimfunc = <<-EOF
					function! #{methodName}(#{args})
						ruby ret = VIM.#{methodName}();
						ruby VIM.command (%[let ret = "\#{ret}"]) if ret          #the \# is to avoid this from being interpreted when the function is defined
						if exists("ret")
							return ret
						endif
					endfunction
				EOF
			else
				vimfunc = <<-EOF
					function! #{methodName}(#{args})
						ruby ret = VIM.#{methodName}(*VIM.get_args(#{arity}, #{vararg}));
						ruby VIM.command (%[let ret = "\#{ret}"]) if ret          #the \# is to avoid this from being interpreted when the function is defined
						if exists("ret")
							return ret
						endif
					endfunction
				EOF
			end
			p vimfunc if (defined?($vimRubyDebug) && $vimRubyDebug)
			VIM << vimfunc
		end

		def Eval_rb()
            begin
                line = ''
                indent=0
                $stdout.sync = TRUE
                lInput =  "ruby> "
                while TRUE
                    l = gets(lInput)
                    unless l
                        break if line == ''
                    else
                        line = line + "\n" + l 
                        case l
                            when /,\s*$/
                                lInput =  "ruby| "
                                next
                            when /^\s*(class|module|def|if|unless|case|while|until|for|begin)\b/
                                indent += 1

                            when /^\s*end\b/
                                indent -= 1

                            when /\{\s*(\|.*\|)?\s*$/
                                indent += 1

                            when /^\s*\}/
                                indent -= 1
                            when /^\s*exit\b/
                                break
                        end
                        if indent > 0
                            puts "\n"
                            lInput =  "ruby| "
                            next
                        end
                    end
                    begin
                        puts "\n"
                        puts line if (defined?($vimRubyDebug) && $vimRubyDebug)
                        puts  eval(line).inspect
                    rescue ScriptError, StandardError, NameError, ArgumentError => boom
                        puts  "ERR: ", boom, "\n"
                        puts "while evaluating line #{line}"
                        puts boom.backtrace
                    end

                    break if not l
                    line = ''
                    lInput =  "ruby> "
                end
                puts "\n"
            end
        rescue Exception => boom
            puts  "ERR: ", boom, "\n"
            puts "while evaluating line #{line}"
            puts boom.backtrace 
        end
	end
end

VIM << "command! EvalRb call Eval_rb()"
puts "Vim Ruby support updated"   if (defined?($vimRubyDebug) && $vimRubyDebug)
EORUBY
