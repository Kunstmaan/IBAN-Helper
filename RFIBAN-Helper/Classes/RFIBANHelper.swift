
import Foundation

public enum IbanCheckStatus: Int {
  case validIban
  case invalidCountryCode
  case invalidBankAccount
  case invalidChecksum
  case invalidInnerStructure
  case invalidStartBytes
  @available(*, deprecated: 2.0.1, message: "Pleaes use `invalidStructure` instead")
  case invalidCharacters
  case invalidLength
  case invalidStructure
}

public class RFIBANHelper: NSObject {

  static let ibanStructure = "^([A-Za-z0-9]{4,})*$"

  static let decimalsAndCharacters = "^([A-Za-z0-9])*$"
  static let decimalsAndUppercaseCharacters = "^([A-Z0-9])*$"
  static let decimalsAndLowercaseCharacters = "^([a-z0-9])*$"
  static let characters = "^([A-Za-z])*$"
  static let decimals = "^([0-9])*$"
  static let lowercaseCharacters = "^([a-z])*$"
  static let uppercaseCharacters = "^([A-Z])*$"

  static let startBytesRegex = "^([A-Z]{2}[0-9]{2})$"

  public static func createIBAN(_ account: String, bic: String? = nil, countryCode: String? = nil) -> String {

    if account.characters.count < 1
    {
      return String()
    }

    if let bic = bic {
      //ISO 9362:2009 states the SWIFT code should be either 8 or 11 characters.
      if bic.characters.count != 8 && bic.characters.count != 11
      {
        return String()
      }

      let countryCode = bic.substring(with: Range<String.Index>(bic.characters.index(bic.startIndex, offsetBy: 4)..<bic.characters.index(bic.startIndex, offsetBy: 6)))
      let bankCode = bic.substring(to: bic.characters.index(bic.startIndex, offsetBy: 4))

      let structure = RFIBANHelper.ibanStructure(countryCode)

      guard let requiredLength = structure["Length"] as? Int else {
        preconditionFailure("Missing length for \(countryCode)")
      }
      let accountNumber = RFIBANHelper.preFixZerosToAccount(account, length: requiredLength - 4)

      let ibanWithoutChecksum = "\(countryCode)00\(bankCode)\(accountNumber)"

      let checksum = RFIBANHelper.checkSumForIban(ibanWithoutChecksum, structure: structure)

      return "\(countryCode)\(checksum)\(bankCode)\(accountNumber)"
    }

    if let countryCode = countryCode {
      let structure = RFIBANHelper.ibanStructure(countryCode)

      let ibanWithoutChecksum = "\(countryCode)00\(account)"

      let checksum = RFIBANHelper.checkSumForIban(ibanWithoutChecksum, structure: structure)

      return "\(countryCode)\(checksum)\(account)"
    }

    return ""
  }

  public static func isValidIBAN(_ iban: String) -> IbanCheckStatus {
    if iban.range(of: RFIBANHelper.ibanStructure, options: .regularExpression) == nil
    {
      return .invalidStructure
    }

    let countryCode = iban.substring(with: Range<String.Index>(iban.startIndex..<iban.characters.index(iban.startIndex, offsetBy: 2)))

    let structure = RFIBANHelper.ibanStructure(countryCode)

    if structure.keys.count == 0
    {
      return .invalidCountryCode
    }

    if iban.substring(with: Range<String.Index>(
    iban.startIndex..<iban.characters.index(iban.startIndex, offsetBy: 4))).range(
      of: RFIBANHelper.startBytesRegex,
      options: .regularExpression) == nil
    {
      return .invalidStartBytes
    }

    let nf = NumberFormatter()
    guard let innerStructure = structure["InnerStructure"] as? String else {
      preconditionFailure("Missing Innerstructure for \(countryCode)")
    }

    var bbanOfset = 0
    let bban = iban.substring(from: iban.characters.index(iban.startIndex, offsetBy: 4))

    if bban.isEmpty {
      return .invalidBankAccount
    }
    
    for i in 0...(innerStructure.characters.count/3)-1
    {
      let startIndex = i * 3

      let format = innerStructure.substring(with: Range<String.Index>(innerStructure.characters.index(innerStructure.startIndex, offsetBy: startIndex)..<innerStructure.characters.index(innerStructure.startIndex, offsetBy: startIndex + 3)))


      guard let formatLength = Int(innerStructure.substring(with: Range<String.Index>(innerStructure.characters.index(innerStructure.startIndex, offsetBy: startIndex + 1)..<innerStructure.characters.index(innerStructure.startIndex, offsetBy: startIndex + 3)))),
            let innerPartEndIndex = bban.characters.index(bban.startIndex, offsetBy: bbanOfset + formatLength, limitedBy: bban.endIndex) else {
        return .invalidInnerStructure
      }

      let innerPart = bban.substring(with: Range<String.Index>(bban.characters.index(bban.startIndex, offsetBy: bbanOfset)..<innerPartEndIndex))

      if RFIBANHelper.isStringConformFormat(innerPart, format: format) == false
      {
        return .invalidInnerStructure
      }

      bbanOfset = bbanOfset + formatLength
    }

    //  1. Check that the total IBAN length is correct as per the country. If not, the IBAN is invalid.
    if let expectedLength = structure["Length"] as? NSNumber
    {
      if expectedLength.intValue != iban.characters.count
      {
        return .invalidLength
      }
    }

    guard let expectedCheckSum = nf.number(from: iban.substring(with: Range<String.Index>(iban.characters.index(iban.startIndex, offsetBy: 2)..<iban.characters.index(iban.startIndex, offsetBy: 4)))) else {
      return .invalidChecksum
    }

    if expectedCheckSum.intValue == RFIBANHelper.checkSumForIban(iban, structure:structure)
    {
      return .validIban
    }

    return .invalidChecksum
  }

  public static func isStringConformFormat(_ string: String, format: String) -> Bool
  {
    if string.isEmpty || format.isEmpty
    {
      return false
    }

    let formatLength = Int(format.substring(from: format.characters.index(format.startIndex, offsetBy: 1)))

    if formatLength != string.characters.count
    {
      return false
    }

    switch format.characters.first! {
    case "A":
      return string.range(of: RFIBANHelper.decimalsAndCharacters, options: .regularExpression) != nil

    case "B":
      return string.range(of: RFIBANHelper.decimalsAndUppercaseCharacters, options: .regularExpression) != nil

    case "C":
      return string.range(of: RFIBANHelper.characters, options: .regularExpression) != nil

    case "F":
      return string.range(of: RFIBANHelper.decimals, options: .regularExpression) != nil

    case "L":
      return string.range(of: RFIBANHelper.lowercaseCharacters, options: .regularExpression) != nil

    case "U":
      return string.range(of: RFIBANHelper.uppercaseCharacters, options: .regularExpression) != nil

    case "W":
      return string.range(of: RFIBANHelper.decimalsAndLowercaseCharacters, options: .regularExpression) != nil

    default:
      return false
    }
  }

  public static func ibanStructure(_ countryCode: String) -> [String: Any] {

    if let path = Bundle(for: object_getClass(self)).path(forResource: "IBANStructure", ofType: "plist") {
      if let ibanStructureList = NSArray(contentsOfFile:path) as? [[String: Any]] {
        for ibanStructure in ibanStructureList {
          if ibanStructure["Country"] as? String == countryCode {
            return ibanStructure
          }
        }
      }
    }

    return [:]
  }

  public static func checkSumForIban(_ iban: String, structure: [String: Any]) -> Int {
    //  2. Replace the two check digits by 00 (e.g., GB00 for the UK).
    //  3. Move the four initial characters to the end of the string.
    let bankCode = iban.substring(from: iban.characters.index(iban.startIndex, offsetBy: 4))
    let countryCode = iban.substring(to: iban.characters.index(iban.startIndex, offsetBy: 2))
    var checkedIban = "\(bankCode)\(countryCode)00"

    //  4. Replace the letters in the string with digits, expanding the string as necessary, such that A or
    //  a = 10, B or b = 11, and Z or z = 35. Each alphabetic character is therefore replaced by 2 digits.
    //  5. Convert the string to an integer (i.e., ignore leading zeroes).
    checkedIban = RFIBANHelper.intValueForString(checkedIban.uppercased())

    //  6. Calculate mod-97 of the new number, which results in the remainder.

    let remainder = ISO7064.MOD97_10(checkedIban)

    //  7.Subtract the remainder from 98, and use the result for the two check digits. If the result is a single digit number,
    //  pad it with a leading 0 to make a two-digit number.

    return 98 - remainder;
  }

 

  public static func intValueForString(_ string: String) -> String {
    if string.range(of: RFIBANHelper.decimalsAndUppercaseCharacters, options: .regularExpression) == nil
    {
      return ""
    }

    let returnValue = NSMutableString()

    for charValue in string.unicodeScalars {

      var decimalCharacter = 0

      // 0-9
      if charValue.value >= 48 && charValue.value <= 57 {
        decimalCharacter = Int(charValue.value) - 48
      } else if charValue.value >= 65 && charValue.value <= 90 {
        decimalCharacter = Int(charValue.value) - 55
      }

      returnValue.append(String(decimalCharacter))
    }

    return returnValue as String
  }

  public static func preFixZerosToAccount(_ bankNumber: String, length: Int) -> String {

    var banknumberWithPrefixes = bankNumber

    for _ in bankNumber.characters.count...length {
      banknumberWithPrefixes = String(format:"0%@", bankNumber)
    }

    return banknumberWithPrefixes;
  }
}
