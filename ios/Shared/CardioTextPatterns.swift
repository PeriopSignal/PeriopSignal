import Foundation

// MARK: - The patterns of the cardiopulmonary-test reader (CardioText)
//
// Generated from the Python model the reader was written and tested in (SP/cardiotext/cardio.py, tables.py): every pattern is
// the model's, character for character, so the two cannot drift. The tests of T112Tests are generated from the same tables.

enum CardioRx {
    static let aorta = NoteRx(#"\b(?:aorta\s+(?:intact|nl|normal|wnl)|(?:normal|nl|intact)\s+aorta)\b"#)
    static let arteryWords = NoteRx(#"\b(?:ica|icas|carotid|internal\s+carotid|radial|radials|artery|arteries)\b"#)
    static let carBareNormal = NoteRx(#"^\s*[:\-–]?\s*(?:normal|nl|wnl|no\s+(?:significant\s+)?stenosis)\b"#)
    static let carSten = NoteRx(#"(?<![\d.])(?:(?:([<≤≥>])\s*(\d{1,3})\s*%?|(\d{1,3})\s*[-–]\s*(\d{1,3})\s*%|(\d{1,3})\s*%)|(near[- ]occlu(?:sion|ded)|string\s+sign|occlu(?:ded|sion)|no\s+(?:significant\s+)?stenosis|normal|nl|wnl))(?![\d/])(?:\s+stenosis\b)?"#)
    static let carVel = NoteRx(#"\b(psv|edv)\b\s*(?:of\s+|:\s*|=\s*)?(\d{2,3})(?:\s*cm/s)?(?![\d/])"#)
    static let carVert = NoteRx(#"\b(?:vertebral|vert)(?:\s+(?:flow|artery|arteries))?\s*(?:is\s+|was\s+|:\s*|=\s*)?(antegrade|retrograde|reversed|absent|partial\s+reversal)\b|\b(antegrade|retrograde|reversed|absent|partial\s+reversal)\s+(?:vertebral|vert)\b"#)
    static let chamberFull = NoteRx(#"^(?:lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))$"#)
    static let cmpBefore = NoteRx(#"[<>≤≥]\s*$"#)
    static let cueCarotid = NoteRx(#"\bcarotid\s+(?:us|u/s|ultrasound|duplex|dopplers?)\b"#)
    static let cueCarotids = NoteRx(#"\bcarotids\b"#)
    static let cueCath = NoteRx(#"(?<!\bpa )(?<!\bart )(?<!arterial )(?<!venous )(?<!central )(?<!foley )(?<!urinary )(?<!swan )(?<!swan-ganz )(?<!\bpicc )(?<!\bcvc )(?<!suprapubic )(?<!epidural )(?<!\bpd )(?<!\bhd )(?<!dialysis )(?<!tunneled )(?<!tunnelled )\bcath(?:eterization|eterisation)?\b(?!\s+lab)|(?<!clean )(?<!normal )\bcors\b"#)
    static let cueCxr = NoteRx(#"\b(?:(normal|nl|clear|unremarkable)\s+)?(?:cxr|chest\s*x[- ]?rays?|chest\s+films?|chest\s+radiographs?)\b"#)
    static let cueEcho = NoteRx(#"(?<!stress )(?<!dobutamine )(?<!bubble )(?<!contrast )(?<!exercise )(?<!stress-)\b(?:echo|echos|echocardiograms?|echocardiography|tte|(?-i:TEE))\b(?!\s+(?:probe|screen\w*|machine|cart|room|lab|tech\w*|bed))"#)
    static let cueLhc = NoteRx(#"(?<!\bct )(?<!\bcta )(?<!\bccta )(?<!\bmr )(?<!\bmra )\b(?:lhc|left\s+heart\s+cath(?:eterization|eterisation)?|coronary\s+angiogra(?:m|phy))\b"#)
    static let cuePft = NoteRx(#"\b(?:(normal|nl|wnl)\s+)?(?:pfts?|spirometry|pulmonary\s+function\s+test(?:s|ing)?)\b"#)
    static let cueRadial = NoteRx(#"\bradial\s+(?:artery\s+)?(?:us|u/s|ultrasound|duplex)\b"#)
    static let cueRhc = NoteRx(#"\b(?:rhc|right\s+heart\s+cath(?:eterization|eterisation)?|swan\s+numbers)\b"#)
    static let cxrEff1 = NoteRx(#"(?<![A-Za-z])(?:(small|sm|moderate|mod|large|lg)\s+)?(?:(left|l|right|r|bilateral|bilat|b/l|both)(?:[- ]?sided)?\s+)?(?:pleural\s+)?(eff(?:usions?)?)\b"#)
    static let cxrEff2 = NoteRx(#"(?<![A-Za-z])(?:(left|l|right|r|bilateral|bilat|b/l|both)(?:[- ]?sided)?\s+)?(?:(small|sm|moderate|mod|large|lg)\s+)?(?:pleural\s+)?(eff(?:usions?)?)\b"#)
    static let cxrExam = NoteRx(#"\b(?:auscultation|ctab?|breath\s+sounds|bs\b|percussion|wheez\w*|rales|rhonchi|crackles)"#)
    static let cxrNegStart = NoteRx(#"^(?:no|not|without|denies|neg(?:ative)?|absence|absent|free\s+of|resolved|resolution)\b"#)
    static let cxrNormal = NoteRx(#"\b(?:normal|nl|clear(?!\s+(?:to|on|bilat\w*|lungs?|bs|breath\w*|b/l))|wnl|nad|nacpd|unremarkable|no\s+acute\s+(?:cardiopulmonary\s+)?(?:process|disease|findings?))\b"#)
    static let cxrSegment = NoteRx(#"[^|,;:()]+"#)
    static let cxrVocab = NoteRx(#"\b(?:infiltrates?|infiltration|opacit\w+|consolidation|atelectasis|cardiomegaly|cardiac\s+silhouette|edema|congestion|hyperinflat\w+|pneumothorax|ptx|nodules?|masse?s?|lesions?|scarring|fibrosis|cephalization|kerley|pleural\s+thickening|hilar|mediastin\w+|sternal\s+wires?|pna|pneumonia|effusions?|haziness|hazy|blunting|hemidiaphragm|widened|rll|rul|rml|lll|lul|bibasilar|basilar)\b"#)
    static let cxrWo = NoteRx(#"^w/o\b"#)
    static let cxrWords = NoteRx(#"\b(?:eff(?:usions?)?|clear|normal|nl|lungs?|heart|hila\w*|mediastin\w+|costophrenic|diaphragm\w*|base|bases|lobe|rll|rml|rul|lll|lul|lingula\w*|pna|pneumonia|chf|copd)\b"#)
    static let dateAfter = NoteRx(#"^[\s:(\-–]*(?:(?:on|from|in|dated|done)\s+)?((?<![\d/.\-])(?:(?:0?[1-9]|1[0-2])[/.\-](?:(?:19|20)\d\d|\d\d)(?![\d/])|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(?:(?:19|20)\d\d|\d\d)(?![\d/])|(?:19|20)\d\d(?![\d/%])))\)?"#)
    static let dateBefore = NoteRx(#"((?<![\d/.\-])(?:(?:0?[1-9]|1[0-2])[/.\-](?:(?:19|20)\d\d|\d\d)(?![\d/])|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(?:(?:19|20)\d\d|\d\d)(?![\d/])|(?:19|20)\d\d(?![\d/%])))\s*(?:(?:echo|tte|tee|study)\s*)?$"#)
    static let echoKnown: [NoteRx] = [
        NoteRx(#"\b(?:rvsp|pasp|rap)\s*(?:of\s+|:\s*|=\s*)?\d+(?:\.\d+)?(?:\s*mmhg)?"#),
        NoteRx(#"\b(?:la|left\s+atri(?:um|al))\s+(?:size\s+)?(?:(?:is\s+)?(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)\s+)?(?:nl|normal|dilated|dil|enlarged)\b"#),
        NoteRx(#"\b(?:wall\s+motion\s+(?:abnormalit\w+|nl|normal)|rwma|wma|no\s+rwma|no\s+wma|hypokines\w+|akines\w+)\b"#),
        NoteRx(#"\b(?:diastolic\s+(?:dysfunction|dysfxn|function|fxn)(?:\s+grade\s+(?:i{1,3}|iv|[1-4]))?|grade\s+(?:i{1,3}|iv|[1-4])\s+(?:dd|diastolic(?:\s+dysfunction)?)|dd)\b"#),
        NoteRx(#"\b(?:(?:mean|peak|max)\s+)?gradient\s*(?:of\s+|:\s*|=\s*)?\d+(?:\.\d+)?(?:\s*mmhg)?|\b(?:mean|peak)\s+(?:grad|gradient)\s*\d+"#),
        NoteRx(#"\b(?:ava|mva|valve\s+area)\s*(?:of\s+|:\s*|=\s*)?\d+(?:\.\d+)?(?:\s*cm2?)?"#),
        NoteRx(#"\b(?:lvh|rvh|concentric\s+lvh|lv\s+hypertrophy)\b"#),
    ]
    static let effBadBefore = NoteRx(#"(?:pericardial|trace|tiny|massive|loculated|mild|minimal|(?:small|sm|mod|moderate)\s*(?:-|–|/|to)\s*(?:mod|moderate|large|lg)?)\s*$"#)
    static let efHistory = NoteRx(#"\b(?:ef|lvef|ejection fraction)\s*(?:of|is|was|:|=|~|<|>|≤|≥)?\s*(\d{1,2})\s*(?:-|–|to)?\s*(\d{1,2})?\s*%"#)
    static let efRx = NoteRx(#"(?<![A-Za-z])(?:lv\s*)?(?:lvef|ef|ejection\s+fraction)\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(?:approx(?:imately)?\.?\s+|about\s+)?[~≈]?\s*(\d{1,2}(?:\.\d)?)(?:\s*(?:-|–|to)\s*(\d{1,2}(?:\.\d)?))?\s*(%)?(?![\d/])"#)
    static let fillerWords = NoteRx(#"\b(?:with|and|showed|shows|showing|show|w|c/w|reveals?|revealed|notable\s+for|the|a|an|is|was|are|of|on|by|at|in|per|from|study|results?|findings?|impression|report|reported|done|pred|predicted|mmhg|mm\s*hg|l/min|lpm|ml|cm|mm|l|pa/lat(?:eral)?|pa\s+and\s+lat(?:eral)?|ap|portable|upright|today|yesterday)\b|w/(?!o\b)"#)
    static let gradeBefore = NoteRx(#"(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|slightly|borderline)\s*[-–/]?\s*$"#)
    static let gradeStart = NoteRx(#"^(?:mild|mod|sev)"#)
    static let hedgeAfter = NoteRx(#"^\s*(?:\?|\(\s*\?\s*\)|(?:vs\.?|versus|->|→|compared|from|prior|previously|unchanged|same|was)\b|\(\s*(?:prior|previous|previously|was|vs\.?)\b)"#)
    static let leadIn = NoteRx(#"\s*\b(?:on|by|per|in|from|at)\s+(?:the\s+)?(?:(?:last|recent|prior|pre-?op(?:erative)?|repeat)\s+)?$"#)
    static let letterRx = NoteRx(#"[A-Za-z]"#)
    static let lhcDom = NoteRx(#"\b(?:(right|r)[- ]?dom(?:inant|inance)?|(left|l)[- ]?dom(?:inant|inance)?|(co)[- ]?dominan(?:t|ce))\b"#)
    static let lhcKnown: [NoteRx] = [
        NoteRx(#"\b(?:[123]\s*-?\s*vd|[123]\s*-?\s*vessel\s+(?:cad|disease)|mvd|multi-?vessel\s+(?:cad|disease))\b"#),
        NoteRx(#"\b(?:lvedp|edp)\s*(?:of\s+|:\s*|=\s*)?\d+(?:\.\d+)?(?:\s*mmhg)?"#),
        NoteRx(#"\b(?:lv\s*)?(?:lvef|ef|ejection\s+fraction)\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?[~≈]?\s*\d{1,2}(?:\.\d)?(?:\s*(?:-|–|to)\s*\d{1,2}(?:\.\d)?)?\s*%?"#),
        NoteRx(#"\b(?:lv\s*gram|ventriculogram)\b"#),
    ]
    static let lhcOccA = NoteRx(#"\b(?:cto|(?:(?:totally|completely|chronically)\s+)?occluded|(?:total\s+)?occlusion\s+of(?:\s+the)?)\s+(?:(?:(prox(?:imal)?|mid|dist(?:al)?)\s+|(p|m|d)\s?-?(?=(?:lmca|lm|lad|lcx|cx|rca|pda)\b)))?(lmca|lm|left\s+main(?:\s+coronary)?|lad|left\s+anterior\s+descending|lcx|cx|circ|circumflex|rca|right\s+coronary(?:\s+artery)?|pda)\b"#)
    static let lhcOccB = NoteRx(#"\b(?:(?:(prox(?:imal)?|mid|dist(?:al)?)\s+|(p|m|d)\s?-?(?=(?:lmca|lm|lad|lcx|cx|rca|pda)\b)))?(lmca|lm|left\s+main(?:\s+coronary)?|lad|left\s+anterior\s+descending|lcx|cx|circ|circumflex|rca|right\s+coronary(?:\s+artery)?|pda)\s+(?:is\s+)?(?:cto|(?:(?:totally|completely|chronically)\s+)?occluded|(?:total\s+)?occlusion)\b"#)
    static let lhcPctAfter = NoteRx(#"\b(?:(?:(prox(?:imal)?|mid|dist(?:al)?)\s+|(p|m|d)\s?-?(?=(?:lmca|lm|lad|lcx|cx|rca|pda)\b)))?(lmca|lm|left\s+main(?:\s+coronary)?|lad|left\s+anterior\s+descending|lcx|cx|circ|circumflex|rca|right\s+coronary(?:\s+artery)?|pda)\b(?:\s+(?:stenosis|lesion|disease|stenotic))?\s*(?:[:=\-–]\s*|(?:of|is|was|at)\s+)?(\d{1,3})\s*(%)?(?!\d)(?!\s*(?:[-–/]\s*\d|to\s+\d|mm\b|cm\b|vessel|stents?|x\b|×|\.\d))"#)
    static let lhcPctBefore = NoteRx(#"(?<![\d.])(\d{1,3})\s*%\s*(?:stenosis\s+)?(?:(?:of|in)\s+)?(?:the\s+)?(?:(?:(prox(?:imal)?|mid|dist(?:al)?)\s+|(p|m|d)\s?-?(?=(?:lmca|lm|lad|lcx|cx|rca|pda)\b)))?(lmca|lm|left\s+main(?:\s+coronary)?|lad|left\s+anterior\s+descending|lcx|cx|circ|circumflex|rca|right\s+coronary(?:\s+artery)?|pda)\b(?:\s+(?:stenosis|lesion))?"#)
    static let maskGap = NoteRx(#"^[\s:\-–()=]*$"#)
    static let negatedBefore = NoteRx(#"\b(?:no|not|without|w/o|denies|denied|never|absent|neg(?:ative)?\s+for|ruled\s+out|r/o|rule\s+out|possible|probable|likely|suspect(?:ed)?|borderline|questionable|\?)\W+(?:\w+\W+){0,2}$"#)
    static let notDoneAfter = NoteRx(#"^\s*[:\-–]?\s*(?:(?:is|was|has\s+been|to\s+be|still|not\s+yet)\s+)*(?:pending|ordered|scheduled|sched|planned|recommended|not\s+(?:done|performed|yet|completed|available|obtained|on\s+file)|never\s+(?:done|had|performed)|awaiting|declined|refused|deferred|to\s+be\s+done|cancel\w*|needed|unable\s+to\s+(?:complete|tolerate|perform|do|obtain)|to\s+be\s+(?:done|scheduled|ordered|obtained)|tomorrow|later|in\s+(?:the\s+)?(?:am|morning)|next\s+week|on\s+(?:mon|tue|wed|thu|fri|sat|sun)\w*)\b"#)
    static let notDoneBefore = NoteRx(#"\b(?:no|not|never|without|denies|w/o|pending|ordered|scheduled|sched|planned|plan|plans|planning|will|would|check|checking|await|possible|possibly|if|unless|recommend\w*|needs?|needed|consider\w*|should\s+(?:have|get|undergo)|awaiting|declined|refused|deferred|unable\s+to\s+(?:do|complete|perform|tolerate|get|obtain)|to\s+(?:have|get|undergo|obtain|do)|will\s+(?:have|get|need|undergo)|get|getting|obtain|request\w*|order(?:ing)?|due(?:\s+for)?)\s+(?:(?:an?|the|for|to\s+have|had|prior|previous|recent|any|formal|record\s+of|repeat|outpatient|preop\w*|further|new|updated|stat|urgent|bedside|limited|complete|prelim\w*|cardiac|coronary|diagnostic|portable)\s+)*$"#)
    static let numbers = NoteRx(#"\d+(?:\.\d+)?"#)
    static let ownForm = NoteRx(#"\b(?:sev|triv)\b"#)
    static let pairAfter = NoteRx(#"^\s*(?:and|&|/|\+)\s*(?:rv|lv)\b"#)
    static let pairBefore = NoteRx(#"\b(?:rv|lv)\s*(?:and|&|/|\+)\s*$"#)
    static let pendingGap = NoteRx(#"^\s*(?:(?:in|of)\s+)?(?:the\s+)?$"#)
    static let pftDlco = NoteRx(#"\bdlco\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,3}(?:\.\d)?)\s*%(?:\s*pred(?:icted)?)?(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let pftKnown: [NoteRx] = [
        NoteRx(#"\bgold\s*(?:stage\s*|grade\s*)?[1-4]\b"#),
        NoteRx(#"\b(?:post|pre)[- ]?(?:bd|bronchodilator)\b|\bbronchodilator\s+(?:response|reversibility)\b|\breversib\w+"#),
    ]
    static let pftNormalAfter = NoteRx(#"^\s*[:\-–]?\s*(normal|nl|wnl)\b(?!\s+(?:dlco|tlc|fev\s?1|fvc|ratio|lung|diffusion|spirometry))"#)
    static let pftPattern = NoteRx(#"\b(?:(mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)\s+)?(obstructive|obstruction|obs|restrictive|restriction|mixed|nonspecific|non-specific)(?:\s+(?:pattern|defect|disease|ventilatory\s+defect|lung\s+disease))?(?:\s+(mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)\b)?"#)
    static let pftRatio = NoteRx(#"\bfev\s?1\s*/\s*fvc\b\s*(?:ratio\s*)?(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d*\.?\d+)\s*(%)?(?![\d/])|\bratio\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d*\.?\d+)\s*(%)?(?![\d/])"#)
    static let pftTlc = NoteRx(#"\btlc\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,3}(?:\.\d)?)\s*%(?:\s*pred(?:icted)?)?(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let pftVol = NoteRx(#"\b(fev\s?1|fvc)\b(?!\s*/)\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d*\.?\d+)\s*(l\b|liters?\b|litres?\b|%)?(?:\s*(?:pred(?:icted)?)\b)?(?:\s*\(?\s*(\d*\.?\d+)\s*(%|l\b)\s*(?:pred(?:icted)?)?\s*\)?)?(?![\d/])(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let plannedBefore = NoteRx(#"\b(?:for|undergoing)\s+(?:(?:an?|the|elective|urgent|emergent|diagnostic|repeat|outpatient|cardiac|coronary)\s+)*$"#)
    static let punctOnly = NoteRx(#"^[\s:\-–—=~()/%.<>≤≥≈?+*]*$"#)
    static let qOrCmpBefore = NoteRx(#"(?:\?|[<>≤≥])\s*$"#)
    static let radCalc = NoteRx(#"\b(no\s+calcification|not\s+calcified|calcified|calcification)\b"#)
    static let radDiam = NoteRx(#"(?<![\d.])(\d(?:\.\d{1,2})?)\s*mm\b"#)
    static let radHarvest = NoteRx(#"(?<!no )(?<!not )(?<!avoid )\bharvest\s+(left|right)\b|\bno\s+harvest\b(?!\s*(?:of\s+|on\s+|from\s+)?(?:the\s+)?(?:l|r|left|right|lt|rt)\b)"#)
    static let radUlnar = NoteRx(#"\bulnar(?:\s+(?:compensation|artery|flow|collateral))?\s*(?:is\s+|:\s*|=\s*)?(adequate|inadequate)\b|\b(adequate|inadequate)\s+ulnar\b"#)
    static let rhcCo = NoteRx(#"\b(?:co|cardiac\s+output)\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,2}(?:\.\d{1,2})?)(?:\s*l\s*/\s*min|\s*lpm)?(?![\d/%.])(?!\s*%)(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let rhcKnown: [NoteRx] = [
        NoteRx(#"\brv\s*(?:of\s+|:\s*|=\s*)?\d{1,3}\s*/\s*\d{1,3}(?:\s*/\s*\d{1,3})?(?:\s*mm\s*hg)?"#),
        NoteRx(#"\b(?:fick|td|thermodilution|thermo)\b"#),
        NoteRx(#"\b(?:ci|cardiac\s+index|pvr|svr|svo2|tpg|dpg|mixed\s+venous)\b\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?\d*(?:\.\d+)?(?:\s*(?:wu|woods?\s+units?|dyn\w*|%|l/min/m2))?"#),
    ]
    static let rhcPa = NoteRx(#"\b(?:pa|pap)\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,3})\s*/\s*(\d{1,3})(?:\s*(?:/|\(\s*(?:mean\s*(?:of\s+)?)?|,?\s*(?:with\s+(?:a\s+)?)?mean\s*(?:of\s+)?|\bm\b\s*)\s*(\d{1,3})(?:\s*mm\s*hg)?\)?)?(?:\s*mm\s*hg)?(?![\d/%])"#)
    static let rhcPam = NoteRx(#"\b(?:mpap|pa\s+mean|mean\s+pa(?:p)?|pam)\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,3})(?:\s*mm\s*hg)?(?![\d/%.])(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let rhcPasp = NoteRx(#"\b(pasp|padp)\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,3})(?:\s*mm\s*hg)?(?![\d/%.])(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let rhcPcwp = NoteRx(#"\b(?:pcwp|pawp|pcw|wedge)\s*(?:pressure\s*)?(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,2}(?:\.\d)?)(?:\s*mm\s*hg)?(?![\d/%.])(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let rhcRa = NoteRx(#"\b(?:ra|rap|ra\s+pressure|right\s+atrial(?:\s+pressure)?)\s*(?:of\s+|is\s+|was\s+|:\s*|=\s*)?(\d{1,2}(?:\.\d)?)(?:\s*mm\s*hg)?(?![\d/%.])(?!\s*%)(?!\s*(?:[-–]\s*\d|to\s+\d))"#)
    static let runVeto = NoteRx(#"\b(?:now|currently|prior|previous(?:ly)?|formerly|old|earlier|baseline|improv\w+|worse\w*|worsen\w+|resolv\w+|increas\w+|decreas(?:e|es|ing)\b|progress\w+|interval|unchanged|stable|since|compared|comparison|vs\.?|versus|h/o|history\s+of|repeat|then|later|previously|up\s+from|down\s+from|probabl[ey]|possibl[ey]|appears?|apparent(?:ly)?|likely|suspect\w*|questionable|equivocal|cannot\s+(?:exclude|rule)|can't\s+(?:exclude|rule)|may\s+(?:be|have|represent)|question\w*|limited|suboptimal|poor\s+(?:windows?|quality)|technically\s+difficult|estimated\s+by|not\s+(?:well\s+)?(?:seen|visuali[sz]ed|assessed|measured|reported))\b|->|→|=>|\?"#)
    static let sentBreak = NoteRx(#"\n|\.(?=\s|$)"#)
    static let sideCombine = NoteRx(#"^\s*(?:and|&|/|\+)\s*$"#)
    static let sideGap = NoteRx(#"^[\s:=\-–,(]*(?:(?:is|has|of|with|flow|ica|stenosis|doppler|velocity|velocities|measures)\s+)*$"#)
    static let sideToken = NoteRx(#"(?<![A-Za-z])(?:(bilaterally|bilateral|bilat|b/l|both)|(rica|right|r)|(lica|left|l))(?![A-Za-z])(?:\s+(?:ica|internal\s+carotid|carotid|radial(?:\s+artery)?))?"#)
    static let vetoBears = NoteRx(#"\d|\b(?:normal|nl|wnl|mild\w*|mod\w*|sev\w*|clear|dilated|reduced|occluded)\b"#)
    static let vAfter = NoteRx(#"(?<![A-Za-z])((?-i:AS|AR|AI|MS|MR|TS|TR|TI))(?:\s+(?:is|was)\s+|\s*[:\-–]\s*|\s+)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical))(?:(?:\s*[-–/]\s*|\s+to\s+|-to-)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)))?\b(?!\s*(?:valve\s+)?(?:(?-i:[AMTP][SRI])\b|aortic|mitral|tricuspid|pulmonic|pulmonary))"#)
    static let vBefore = NoteRx(#"\b((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical))(?:(?:\s*[-–/]\s*|\s+to\s+|-to-)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)))?\s+((?-i:AS|AR|AI|MS|MR|TS|TR|TI))(?:/((?-i:AR|AI)))?\b(?!\s*(?:interval|prolong\w*|segment))"#)
    static let vNegated = NoteRx(#"\b(?:no|without|neg(?:ative)?\s+for)\s+(?:significant\s+|sig\s+|evidence\s+of\s+)?(?:(?-i:AS|AR|AI|MS|MR|TS|TR|TI|PS|PR|PI)\b|aortic|mitral|tricuspid|pulmonic)(?:\s+(?:stenosis|regurgitation|insufficiency|regurg))?"#)
    static let vPulm = NoteRx(#"\b(?:(?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)\s+)?(?-i:PS|PR|PI)\b(?:\s+(?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)\b)?"#)
    static let vWritten = NoteRx(#"(?:\b((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical))(?:(?:\s*[-–/]\s*|\s+to\s+|-to-)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)))?\s+)?\b(aortic|mitral|tricuspid)\s+(?:valve\s+)?(stenosis|regurgitation|insufficiency|regurg)\b(?:(?:\s+(?:is|was)\s+|\s*[:\-–]\s*|\s+)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical))(?:(?:\s*[-–/]\s*|\s+to\s+|-to-)((?:trace|triv(?:ial)?|mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?|critical)))?\b(?!\s*(?:valve\s+)?(?:(?-i:[AMTP][SRI])\b|aortic|mitral|tricuspid|pulmonic|pulmonary)))?"#)
    static let wordRx = NoteRx(#"[A-Za-z]+"#)
    static let echoShapes: [(String, NoteRx)] = [
        ("nsize", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+(?:normal(?:ly)?|nl|wnl|preserved|intact)\s+size\b"#)),
        ("nsize", NoteRx(#"\b(?:normal(?:ly)?|nl|wnl|preserved|intact)\s+size\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\b"#)),
        ("nsize", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+size\s+(?:is\s+)?(?:normal(?:ly)?|nl|wnl|preserved|intact)\b"#)),
        ("nsize", NoteRx(#"\b(?:normal(?:ly)?|nl|wnl|preserved|intact)[- ]sized\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\b"#)),
        ("dilated", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+size\s+(?:is\s+)?(?:dilated|dil|enlarged)\b"#)),
        ("dilated", NoteRx(#"\b(?:dilated|dil|enlarged)\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\b"#)),
        ("dilated", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+(?:is\s+)?(?:dilated|dil|enlarged)\b"#)),
        ("fnormal", NoteRx(#"\b(?:normal(?:ly)?|nl|wnl|preserved|intact)\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))(?:\s+(?:systolic|sys))?(?:\s+(?:function|fxn|func|fx))?\b"#)),
        ("fnormal", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))(?:\s+(?:systolic|sys))?(?:\s+(?:function|fxn|func|fx))?\s*:?\s*(?:is\s+)?(?:normal(?:ly)?|nl|wnl|preserved|intact)\b(?!\s+(?:size|sized))"#)),
        ("fgrade", NoteRx(#"\b((?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)(?:(?:\s*[-–/]\s*|\s+to\s+)(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?))?)\s+(?:reduced|depressed|impaired|decreased)\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))(?:\s+(?:systolic|sys))?(?:\s+(?:function|fxn|func|fx))?\b"#)),
        ("fgrade2", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))(?:\s+(?:systolic|sys))?(?:\s+(?:function|fxn|func|fx))?\s*:?\s*(?:is\s+|was\s+)?((?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)(?:(?:\s*[-–/]\s*|\s+to\s+)(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?))?)\s+(?:reduced|depressed|impaired|decreased)\b"#)),
        ("fgrade3", NoteRx(#"\b((?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)(?:(?:\s*[-–/]\s*|\s+to\s+)(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?))?)\s+(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+(?:(?:systolic|sys)\s+)?(?:dysfunction|dysfxn)\b"#)),
        ("fgrade4", NoteRx(#"\b(lvsf|rvsf|lv|rv|left\s+ventric(?:le|ular)|right\s+ventric(?:le|ular))\s+(?:(?:systolic|sys)\s+)?(?:dysfunction|dysfxn)\s+(?:is\s+)?((?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?)(?:(?:\s*[-–/]\s*|\s+to\s+)(?:mild(?:ly)?|mod(?:erate(?:ly)?)?|sev(?:ere(?:ly)?)?))?)\b"#)),
    ]
}
