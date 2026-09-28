// Monthly budget on the resource group. Warns early by email; when actual spend reaches the full
// amount it also fires the kill switch action group. Note: cost data lags by several hours, so the
// execution-count alert in killswitch.bicep is the fast path and this is the backstop.
param namePrefix string
param alertEmail string
param killSwitchActionGroupId string
param amount int = 5

@description('First day of the month the budget starts (yyyy-MM-01).')
param startDate string

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-${namePrefix}'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: { startDate: startDate }
    notifications: {
      firstEuroSpent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 20
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
      }
      forecastOverBudget: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: [alertEmail]
      }
      budgetExhausted: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
        contactGroups: [killSwitchActionGroupId]
      }
    }
  }
}
