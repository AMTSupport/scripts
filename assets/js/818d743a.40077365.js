"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[5699],{3762:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>o,contentTitle:()=>r,default:()=>u,frontMatter:()=>l,metadata:()=>s,toc:()=>d});var a=t(3274),i=t(6906);const l={id:"Get-VarOrSave",title:"Get-VarOrSave",description:'Help page for the "Get-VarOrSave" command',keywords:["PowerShell","Help","Documentation"],hide_title:!1,hide_table_of_contents:!1},r=void 0,s={id:"modules/common/Utils/Get-VarOrSave",title:"Get-VarOrSave",description:'Help page for the "Get-VarOrSave" command',source:"@site/docs/modules/common/00-Utils/Get-VarOrSave.mdx",sourceDirName:"modules/common/00-Utils",slug:"/modules/common/Utils/Get-VarOrSave",permalink:"/scripts/docs/modules/common/Utils/Get-VarOrSave",draft:!1,unlisted:!1,editUrl:"https://github.com/AMTSupport/scripts/tree/master/docs/docs/modules/common/00-Utils/Get-VarOrSave.mdx",tags:[],version:"current",frontMatter:{id:"Get-VarOrSave",title:"Get-VarOrSave",description:'Help page for the "Get-VarOrSave" command',keywords:["PowerShell","Help","Documentation"],hide_title:!1,hide_table_of_contents:!1},sidebar:"ModulesSidebar",previous:{title:"Get-ReturnType",permalink:"/scripts/docs/modules/common/Utils/Get-ReturnType"},next:{title:"Install-ModuleFromGitHub",permalink:"/scripts/docs/modules/common/Utils/Install-ModuleFromGitHub"}},o={},d=[{value:"SYNOPSIS",id:"synopsis",level:2},{value:"SYNTAX",id:"syntax",level:2},{value:"DESCRIPTION",id:"description",level:2},{value:"EXAMPLES",id:"examples",level:2},{value:"EXAMPLE 1",id:"example-1",level:3},{value:"PARAMETERS",id:"parameters",level:2},{value:"-VariableName",id:"-variablename",level:3},{value:"-LazyValue",id:"-lazyvalue",level:3},{value:"-Validate",id:"-validate",level:3},{value:"-ProgressAction",id:"-progressaction",level:3},{value:"CommonParameters",id:"commonparameters",level:3},{value:"INPUTS",id:"inputs",level:2},{value:"OUTPUTS",id:"outputs",level:2},{value:"System.String if the environment variable exists or the lazy value if it does not.",id:"systemstring-if-the-environment-variable-exists-or-the-lazy-value-if-it-does-not",level:3},{value:"null if the value didn&#39;t pass the validation.",id:"null-if-the-value-didnt-pass-the-validation",level:3},{value:"NOTES",id:"notes",level:2},{value:"RELATED LINKS",id:"related-links",level:2}];function c(e){const n={a:"a",code:"code",h2:"h2",h3:"h3",p:"p",pre:"pre",...(0,i.R)(),...e.components};return(0,a.jsxs)(a.Fragment,{children:[(0,a.jsx)(n.h2,{id:"synopsis",children:"SYNOPSIS"}),"\n",(0,a.jsx)(n.p,{children:"Get the value of an environment variable or save it if it does not exist."}),"\n",(0,a.jsx)(n.h2,{id:"syntax",children:"SYNTAX"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-powershell",children:"Get-VarOrSave [-VariableName] <String> [-LazyValue] <ScriptBlock> [[-Validate] <ScriptBlock>]\n [-ProgressAction <ActionPreference>] [<CommonParameters>]\n"})}),"\n",(0,a.jsx)(n.h2,{id:"description",children:"DESCRIPTION"}),"\n",(0,a.jsx)(n.p,{children:"This function will get the value of an environment variable or save it if it does not exist.\nIt will also validate the value if a test script block is provided.\nIf the value does not exist, it will prompt the user for the value and save it as an environment variable,\nThe value will be saved as a process environment variable."}),"\n",(0,a.jsx)(n.h2,{id:"examples",children:"EXAMPLES"}),"\n",(0,a.jsx)(n.h3,{id:"example-1",children:"EXAMPLE 1"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-powershell",children:"Get-VarOrSave `\n    -VariableName 'HUDU_KEY' `\n    -LazyValue { Get-UserInput -Title 'Hudu API Key' -Question 'Please enter your Hudu API Key' };\n"})}),"\n",(0,a.jsx)(n.h2,{id:"parameters",children:"PARAMETERS"}),"\n",(0,a.jsx)(n.h3,{id:"-variablename",children:"-VariableName"}),"\n",(0,a.jsx)(n.p,{children:"The name of the environment variable to get or save."}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-yaml",children:"Type: String\nParameter Sets: (All)\nAliases:\n\nRequired: True\nPosition: 1\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,a.jsx)(n.h3,{id:"-lazyvalue",children:"-LazyValue"}),"\n",(0,a.jsx)(n.p,{children:"The script block to execute if the environment variable does not exist."}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: True\nPosition: 2\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,a.jsx)(n.h3,{id:"-validate",children:"-Validate"}),"\n",(0,a.jsx)(n.p,{children:"The script block to test the value of the environment variable or the lazy value."}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 3\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,a.jsx)(n.h3,{id:"-progressaction",children:"-ProgressAction"}),"\n",(0,a.jsx)(n.p,{children:"{{ Fill ProgressAction Description }}"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-yaml",children:"Type: ActionPreference\nParameter Sets: (All)\nAliases: proga\n\nRequired: False\nPosition: Named\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,a.jsx)(n.h3,{id:"commonparameters",children:"CommonParameters"}),"\n",(0,a.jsxs)(n.p,{children:["This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see ",(0,a.jsx)(n.a,{href:"http://go.microsoft.com/fwlink/?LinkID=113216",children:"about_CommonParameters"}),"."]}),"\n",(0,a.jsx)(n.h2,{id:"inputs",children:"INPUTS"}),"\n",(0,a.jsx)(n.h2,{id:"outputs",children:"OUTPUTS"}),"\n",(0,a.jsx)(n.h3,{id:"systemstring-if-the-environment-variable-exists-or-the-lazy-value-if-it-does-not",children:"System.String if the environment variable exists or the lazy value if it does not."}),"\n",(0,a.jsx)(n.h3,{id:"null-if-the-value-didnt-pass-the-validation",children:"null if the value didn't pass the validation."}),"\n",(0,a.jsx)(n.h2,{id:"notes",children:"NOTES"}),"\n",(0,a.jsx)(n.h2,{id:"related-links",children:"RELATED LINKS"})]})}function u(e={}){const{wrapper:n}={...(0,i.R)(),...e.components};return n?(0,a.jsx)(n,{...e,children:(0,a.jsx)(c,{...e})}):c(e)}},6906:(e,n,t)=>{t.d(n,{R:()=>r,x:()=>s});var a=t(9474);const i={},l=a.createContext(i);function r(e){const n=a.useContext(l);return a.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function s(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:r(e.components),a.createElement(l.Provider,{value:n},e.children)}}}]);