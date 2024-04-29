class Requirement {
}

class PSVersionRequirement : Requirement {
    PSVersionRequirement(
        [Version]$Value
    ) : base('PSVersion', $Value) {}
}

class ModuleRequirement : Requirement {


    ModuleRequirement(
        [String]$Value
    ) : base('Module', $Value) {}
}
