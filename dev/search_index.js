var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = StructHelpers","category":"page"},{"location":"#StructHelpers","page":"Home","title":"StructHelpers","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for StructHelpers.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [StructHelpers]","category":"page"},{"location":"#StructHelpers.@batteries-Tuple{Any, Vararg{Any, N} where N}","page":"Home","title":"StructHelpers.@batteries","text":"@batteries T [options]\n\nAutomatically derive several methods for type T. Supported options are: (eq = true, hash = true, kwconstructor = false, kwshow = false, getproperties = true, constructorof = true)\n\nExample\n\nstruct S\n    a\n    b\nend\n\n@batteries S\n@batteries S hash=false # don't overload `Base.hash`\n@batteries S kwconstructor=true # add a keyword constructor\n\n\n\n\n\n","category":"macro"}]
}