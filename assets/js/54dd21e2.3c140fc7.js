"use strict";(self.webpackChunkdocusaurus=self.webpackChunkdocusaurus||[]).push([[4950],{271:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>a,contentTitle:()=>t,default:()=>p,frontMatter:()=>l,metadata:()=>o,toc:()=>c});var r=s(3274),i=s(6906);const l={id:"Invoke-Progress",title:"Invoke-Progress",description:'Help page for the "Invoke-Progress" command',keywords:["PowerShell","Help","Documentation"],hide_title:!1,hide_table_of_contents:!1},t=void 0,o={id:"modules/common/Logging/Invoke-Progress",title:"Invoke-Progress",description:'Help page for the "Invoke-Progress" command',source:"@site/docs/modules/common/01-Logging/Invoke-Progress.mdx",sourceDirName:"modules/common/01-Logging",slug:"/modules/common/Logging/Invoke-Progress",permalink:"/scripts/docs/modules/common/Logging/Invoke-Progress",draft:!1,unlisted:!1,editUrl:"https://github.com/AMTSupport/scripts/tree/master/docs/docs/modules/common/01-Logging/Invoke-Progress.mdx",tags:[],version:"current",frontMatter:{id:"Invoke-Progress",title:"Invoke-Progress",description:'Help page for the "Invoke-Progress" command',keywords:["PowerShell","Help","Documentation"],hide_title:!1,hide_table_of_contents:!1},sidebar:"ModulesSidebar",previous:{title:"Invoke-Info",permalink:"/scripts/docs/modules/common/Logging/Invoke-Info"},next:{title:"Invoke-Timeout",permalink:"/scripts/docs/modules/common/Logging/Invoke-Timeout"}},a={},c=[{value:"SYNOPSIS",id:"synopsis",level:2},{value:"SYNTAX",id:"syntax",level:2},{value:"DESCRIPTION",id:"description",level:2},{value:"EXAMPLES",id:"examples",level:2},{value:"Example 1",id:"example-1",level:3},{value:"PARAMETERS",id:"parameters",level:2},{value:"-Activity",id:"-activity",level:3},{value:"-FailedProcessItem",id:"-failedprocessitem",level:3},{value:"-Format",id:"-format",level:3},{value:"-Get",id:"-get",level:3},{value:"-Id",id:"-id",level:3},{value:"-Process",id:"-process",level:3},{value:"-Status",id:"-status",level:3},{value:"-ProgressAction",id:"-progressaction",level:3},{value:"CommonParameters",id:"commonparameters",level:3},{value:"INPUTS",id:"inputs",level:2},{value:"None",id:"none",level:3},{value:"OUTPUTS",id:"outputs",level:2},{value:"System.Object",id:"systemobject",level:3},{value:"NOTES",id:"notes",level:2},{value:"RELATED LINKS",id:"related-links",level:2}];function d(e){const n={a:"a",code:"code",h2:"h2",h3:"h3",p:"p",pre:"pre",...(0,i.R)(),...e.components};return(0,r.jsxs)(r.Fragment,{children:[(0,r.jsx)(n.h2,{id:"synopsis",children:"SYNOPSIS"}),"\n",(0,r.jsx)(n.p,{children:"{{ Fill in the Synopsis }}"}),"\n",(0,r.jsx)(n.h2,{id:"syntax",children:"SYNTAX"}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-powershell",children:"Invoke-Progress [[-Id] <Int32>] [[-Activity] <String>] [[-Status] <String>] [-Get] <ScriptBlock>\n [-Process] <ScriptBlock> [[-Format] <ScriptBlock>] [[-FailedProcessItem] <ScriptBlock>]\n [-ProgressAction <ActionPreference>] [<CommonParameters>]\n"})}),"\n",(0,r.jsx)(n.h2,{id:"description",children:"DESCRIPTION"}),"\n",(0,r.jsx)(n.p,{children:"{{ Fill in the Description }}"}),"\n",(0,r.jsx)(n.h2,{id:"examples",children:"EXAMPLES"}),"\n",(0,r.jsx)(n.h3,{id:"example-1",children:"Example 1"}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-powershell",children:"PS C:\\> {{ Add example code here }}\n"})}),"\n",(0,r.jsx)(n.p,{children:"{{ Add example description here }}"}),"\n",(0,r.jsx)(n.h2,{id:"parameters",children:"PARAMETERS"}),"\n",(0,r.jsx)(n.h3,{id:"-activity",children:"-Activity"}),"\n",(0,r.jsx)(n.p,{children:"The activity to display in the progress bar."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: String\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 1\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-failedprocessitem",children:"-FailedProcessItem"}),"\n",(0,r.jsx)(n.p,{children:"The ScriptBlock to invoke when an item fails to process."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 6\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-format",children:"-Format"}),"\n",(0,r.jsx)(n.p,{children:"The ScriptBlock that formats the items name for the progress bar."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 5\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-get",children:"-Get"}),"\n",(0,r.jsx)(n.p,{children:"The ScriptBlock which returns the items to process."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: True\nPosition: 3\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-id",children:"-Id"}),"\n",(0,r.jsx)(n.p,{children:"The ID of the progress bar, used to display multiple progress bars at once."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: Int32\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 0\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-process",children:"-Process"}),"\n",(0,r.jsx)(n.p,{children:"The ScriptBlock to process each item."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: ScriptBlock\nParameter Sets: (All)\nAliases:\n\nRequired: True\nPosition: 4\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-status",children:"-Status"}),"\n",(0,r.jsx)(n.p,{children:"The status message to display in the progress bar.\nThis is formatted with three placeholders:\nThe current completion percentage.\nThe index of the item being processed.\nThe total number of items being processed."}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: String\nParameter Sets: (All)\nAliases:\n\nRequired: False\nPosition: 2\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"-progressaction",children:"-ProgressAction"}),"\n",(0,r.jsx)(n.p,{children:"{{ Fill ProgressAction Description }}"}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-yaml",children:"Type: ActionPreference\nParameter Sets: (All)\nAliases: proga\n\nRequired: False\nPosition: Named\nDefault value: None\nAccept pipeline input: False\nAccept wildcard characters: False\n"})}),"\n",(0,r.jsx)(n.h3,{id:"commonparameters",children:"CommonParameters"}),"\n",(0,r.jsxs)(n.p,{children:["This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see ",(0,r.jsx)(n.a,{href:"http://go.microsoft.com/fwlink/?LinkID=113216",children:"about_CommonParameters"}),"."]}),"\n",(0,r.jsx)(n.h2,{id:"inputs",children:"INPUTS"}),"\n",(0,r.jsx)(n.h3,{id:"none",children:"None"}),"\n",(0,r.jsx)(n.h2,{id:"outputs",children:"OUTPUTS"}),"\n",(0,r.jsx)(n.h3,{id:"systemobject",children:"System.Object"}),"\n",(0,r.jsx)(n.h2,{id:"notes",children:"NOTES"}),"\n",(0,r.jsx)(n.h2,{id:"related-links",children:"RELATED LINKS"})]})}function p(e={}){const{wrapper:n}={...(0,i.R)(),...e.components};return n?(0,r.jsx)(n,{...e,children:(0,r.jsx)(d,{...e})}):d(e)}},6906:(e,n,s)=>{s.d(n,{R:()=>t,x:()=>o});var r=s(9474);const i={},l=r.createContext(i);function t(e){const n=r.useContext(l);return r.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function o(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:t(e.components),r.createElement(l.Provider,{value:n},e.children)}}}]);