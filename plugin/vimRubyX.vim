ruby << EORUBY
module VIM
	Restricted = { :singleton_method_added=>true, :marshall_array=>true, :method_missing=>true, :get_args=>true}
end

def VIM.get_args(arity, vararg)
  args = []
  for i in 1..arity
    args.push VIM.evaluate('a:a' + i.to_s )
  end
  if vararg
    varargs = []
    varity = VIM.evaluate('a:0').to_i
    for i in 1..varity
      varargs.push(VIM.evaluate('a:' + i.to_s))
    end
    args.push(varargs) if varity > 0
  end
  return args
end

def VIM.marshall_array(argv)
    if argv.length == 0
      return ''
    else
      return "'#{argv.join(%q[','])}'"
    end
end

def VIM.method_missing(id, *argv)
	#puts %q(method missing ) + id.to_s
	 VIM::Restricted[id] = true
	 #puts "VIM::Restricted #{VIM::Restricted.inspect}" 
	 #VIM.evaluate('input("waiting")')
     methodName = id.id2name
     raise NameError, %Q(can't find method #{methodName}) unless VIM::evaluate(%Q[exists('*#{methodName}')])
     deffunc = <<-EOEVAL
     def VIM.#{methodName}(*argv)
         VIM.evaluate(%Q(#{methodName}(#{marshall_array(argv)})))
     end
     EOEVAL
	 eval deffunc
	 #puts "method added " + id.to_s + " as " + deffunc
	 VIM.send(methodName, *argv)
end

def VIM.singleton_method_added(id)
  #we need to build our new vim function in a string then put it in a register then eval the register
  #puts "VIM::Restricted #{VIM::Restricted.inspect}"
  if VIM::Restricted[id]
    return 
  end
  methodName = id.id2name
  arity = VIM.method(id).arity
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
  
  #  puts "adding function #{methodName}(#{args}) in vim"
  vimfunc = <<-EOF
  function! #{methodName}(#{args})
    ruby ret = VIM.#{methodName}(*VIM.get_args(#{arity}, #{vararg})); 
    ruby VIM.command (%[let ret = "\#{ret}"]) if ret          #the \# is to avoid this from being interpreted when the function is defined
    if exists("ret")
      return ret
    endif
  endfunction
  EOF
  #p vimfunc
  vimVreg = VIM.evaluate('@y')      #save register
  VIM.command("let @y='#{vimfunc}'")
  VIM.command(":silent @y")                #create the proxy function
  VIM.command("let @y='#{vimVreg}'")   #restore register
end
EORUBY
