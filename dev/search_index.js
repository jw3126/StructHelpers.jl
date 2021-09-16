var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = StructHelpers","category":"page"},{"location":"#StructHelpers","page":"Home","title":"StructHelpers","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for StructHelpers.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [StructHelpers]","category":"page"},{"location":"#StructHelpers.@batteries-Tuple{Any, Vararg{Any, N} where N}","page":"Home","title":"StructHelpers.@batteries","text":"@batteries T [options]\n\nAutomatically derive several methods for type T.\n\nExample\n\nstruct S\n    a\n    b\nend\n\n@batteries S\n@batteries S hash=false # don't overload `Base.hash`\n@batteries S kwconstructor=true # add a keyword constructor\n\nSupported options and defaults are:\n\neq = true:\n\nDefine Base.(==) structurally.\n\nhash = true:\n\nDefine Base.hash structurally.\n\nkwconstructor = false:\n\nAdd a keyword constructor.\n\nkwshow = false:\n\nOverload Base.show such that the names of each field are printed.\n\ngetproperties = true:\n\nOverload ConstructionBase.getproperties.\n\nconstructorof = true:\n\nOverload ConstructionBase.constructorof.\n\n\n\n\n\n","category":"macro"}]
}
