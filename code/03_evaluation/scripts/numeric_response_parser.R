# Match a complete unsigned integer category, allowing surrounding prose.
# Digits within words, signed values, decimal values or exponents are not answers.
numeric_response_pattern <- function(category) {
  sprintf(
    "(*UTF)(*UCP)(?<![\\w.,+\\-\u2212\u2013\u2014])%s(?![\\w]|[.,][0-9])",
    gsub(".", "\\.", category, fixed = TRUE)
  )
}
