// Constraint validation: which controls are barred, which validity flags a
// value trips, and what checkValidity reports.
defineCase({
  name: "form control constraint validation",
  html: "<form id=f>" +
        "<input id=req required>" +
        "<input id=pat pattern='[a-c]+' value='xyz'>" +
        "<input id=num type=number min=1 max=5 step=2 value='4'>" +
        "<input id=mail type=email value='nope'>" +
        "<input id=dis required disabled>" +
        "<input id=ro required readonly>" +
        "<button id=btn type=button></button>" +
        "<fieldset disabled><input id=infs required></fieldset>" +
        "<output id=out></output>" +
        "</form>",
  run(h) {
    const flags = (element) => {
      const v = element.validity;
      const out = {};
      for (const key of ["valueMissing", "typeMismatch", "patternMismatch", "tooLong", "tooShort",
                         "rangeUnderflow", "rangeOverflow", "stepMismatch", "badInput", "customError", "valid"]) {
        if (v[key]) out[key] = true;
      }
      return { willValidate: element.willValidate, flags: out, valid: element.checkValidity() };
    };

    const byId = (id) => document.getElementById(id);
    const report = {};
    for (const id of ["req", "pat", "num", "mail", "dis", "ro", "btn", "infs", "out"]) {
      report[id] = flags(byId(id));
    }

    const custom = byId("pat");
    custom.setCustomValidity("nope");
    report.afterCustomValidity = { ...flags(custom), message: custom.validationMessage.length > 0 };
    custom.setCustomValidity("");
    report.afterClearingCustomValidity = flags(custom);

    report.form = { valid: document.getElementById("f").checkValidity() };
    report.elements = [...document.getElementById("f").elements].map((e) => e.id);
    return report;
  }
});
