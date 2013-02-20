status :published

i18n_prefix = "flow.overseas-passports"
data_query = Calculators::PassportAndEmbassyDataQuery.new 

# Q1
country_select :which_country_are_you_in? do
  save_input_as :current_location

  calculate :passport_data do
    data_query.find_passport_data(responses.last)
  end
  calculate :application_type do
    passport_data[:type]
  end
  calculate :is_ips_application do
    application_type =~ Calculators::PassportAndEmbassyDataQuery::IPS_APPLICATIONS_REGEXP
  end
  calculate :is_fco_application do
    application_type =~ Calculators::PassportAndEmbassyDataQuery::FCO_APPLICATIONS_REGEXP
  end
  calculate :ips_number do
    application_type.split("_")[2] if is_ips_application 
  end
  calculate :embassies_data do
    data_query.find_embassy_data(current_location)
  end
  calculate :embassy_addresses do
    addresses = nil
    unless ips_number.to_i ==  1 or embassies_data.nil?
      addresses = embassies_data.map do |e|
        I18n.translate!("#{i18n_prefix}.phrases.embassy_address",
                        address: e['address'], office_hours: e['office_hours'])
      end
    end
    addresses
  end
  calculate :embassy_address do
    if embassy_addresses
      responses.last =~ /^(russian-federation|pakistan)$/ ? embassy_addresses : embassy_addresses.first
    end
  end
  calculate :embassies_details do
    details = []
    embassies_data.each do |e|
      details << I18n.translate!("#{i18n_prefix}.phrases.embassy_details",
                                address: e['address'], phone: e['phone'],
                                email: e['email'], office_hours: e['office_hours'])
    end if embassies_data
    details
  end
  calculate :embassy_details do
    if embassies_details
      responses.last =~ /^(russian-federation|pakistan)$/ ? embassies_details : embassies_details.first
    end
  end

  calculate :supporting_documents do
    passport_data[:group]
  end

  next_node do |response|
    if Calculators::PassportAndEmbassyDataQuery::NO_APPLICATION_REGEXP.match(response)
      :cannot_apply
    else
      :renewing_replacing_applying?
    end
  end
end

# Q2
multiple_choice :renewing_replacing_applying? do
  option :renewing_new
  option :renewing_old
  option :applying
  option :replacing

  save_input_as :application_action

  next_node :child_or_adult_passport?
end

# Q3
multiple_choice :child_or_adult_passport? do
  option :adult
  option :child

  save_input_as :child_or_adult

  calculate :fco_forms do
    PhraseList.new("#{responses.last}_fco_forms".to_sym)
  end

  next_node do |response|
    case application_type
    when 'australia_post', 'new_zealand'
      "which_best_describes_you_#{response}?".to_sym
    when Calculators::PassportAndEmbassyDataQuery::IPS_APPLICATIONS_REGEXP
      %Q(applying renewing_old).include?(application_action) ? :country_of_birth? : :ips_application_result 
    when Calculators::PassportAndEmbassyDataQuery::FCO_APPLICATIONS_REGEXP
      :fco_result
    else
      :result
    end
  end
end

# Q4
country_select :country_of_birth?, include_uk: true do
  save_input_as :birth_location

  calculate :application_group do
    data_query.find_passport_data(responses.last)[:group]
  end

  calculate :supporting_documents do
    responses.last == 'united-kingdom' ? supporting_documents : application_group
  end

  next_node do |response|
    case application_type
    when 'australia_post', 'new_zealand'
      :aus_nz_result
    when Calculators::PassportAndEmbassyDataQuery::IPS_APPLICATIONS_REGEXP 
      :ips_application_result 
    when Calculators::PassportAndEmbassyDataQuery::FCO_APPLICATIONS_REGEXP
      :fco_result
    else
      :result
    end
  end
end

# QAUS1
multiple_choice :which_best_describes_you_adult? do
  option "born-in-uk-pre-1983" # 4
  option "born-in-uk-post-1982-uk-father" # 5
  option "born-in-uk-post-1982-uk-mother" # 6
  option "born-outside-uk-parents-married" # 7
  option "born-outside-uk-mother-born-in-uk" # 8
  option "born-in-uk-post-1982-father-uk-citizen" # 9
  option "born-in-uk-post-1982-mother-uk-citizen" # 10
  option "born-outside-uk-father-registered-uk-citizen" # 11
  option "born-outside-uk-mother-registered-uk-citizen" # 12
  option "born-in-uk-post-1982-father-uk-service" # 13
  option "born-in-uk-post-1982-mother-uk-service" # 14
  option "married-to-uk-citizen-pre-1983-reg-pre-1988" # 15
  option "registered-uk-citizen" # 16
  option "child-born-outside-uk-father-citizen" # 17
  option "woman-married-to-uk-citizen-pre-1949" # 18

  save_input_as :aus_nz_checklist_variant

  next_node :aus_nz_result
end
# QAUS1 Child specific options
multiple_choice :which_best_describes_you_child? do
  option "born-in-uk-post-1982-uk-father" # 5
  option "born-in-uk-post-1982-uk-mother" # 6
  option "born-outside-uk-parents-married" # 7
  option "born-outside-uk-mother-born-in-uk" # 8
  option "born-in-uk-post-1982-father-uk-citizen" # 9
  option "born-in-uk-post-1982-mother-uk-citizen" # 10
  option "born-in-uk-post-1982-father-uk-service" # 13
  option "born-in-uk-post-1982-mother-uk-service" # 14
  option "registered-uk-citizen" # 16

  save_input_as :aus_nz_checklist_variant

  next_node :aus_nz_result
end

## australia_post/new_zealand result.
outcome :aus_nz_result do
  precalculate :how_long_it_takes do
    PhraseList.new("how_long_#{application_type}".to_sym)
  end
  precalculate :cost do
    PhraseList.new("cost_#{application_type}".to_sym)
  end
  precalculate :how_to_apply do
    PhraseList.new("how_to_apply_#{application_type}".to_sym)
  end
  precalculate :how_to_apply_documents do
    phrases = PhraseList.new("how_to_apply_#{child_or_adult}_#{application_type}".to_sym)

    if application_action == 'replacing' 
      phrases << "aus_nz_replacing".to_sym
    end
    if application_action =~ /^renewing_/
      phrases << "aus_nz_renewing".to_sym
    end

    phrases << "aus_nz_#{aus_nz_checklist_variant}".to_sym
    phrases
  end
  precalculate :receiving_your_passport do
    PhraseList.new("receiving_your_passport_#{application_type}".to_sym)
  end
end


## IPS Application Result 
outcome :ips_application_result do

  precalculate :how_long_it_takes do
    PhraseList.new("how_long_#{application_action}_ips#{ips_number}".to_sym,
                   "how_long_it_takes_ips#{ips_number}".to_sym)
  end
  precalculate :cost do
    PhraseList.new("passport_courier_costs_ips#{ips_number}".to_sym,
                   "#{child_or_adult}_passport_costs_ips#{ips_number}".to_sym,
                   "passport_costs_ips#{ips_number}".to_sym)
  end
  precalculate :how_to_apply do
    PhraseList.new("how_to_apply_ips#{ips_number}".to_sym,
                   supporting_documents.to_sym)
  end
  precalculate :send_your_application do
    PhraseList.new("send_application_ips#{ips_number}".to_sym)
  end
  precalculate :tracking_and_receiving do
    PhraseList.new("tracking_and_receiving_ips#{ips_number}".to_sym)
  end
end

## FCO Result
outcome :fco_result do
  precalculate :how_long_it_takes do
    if application_action == 'applying' and current_location == 'india'
      PhraseList.new(:how_long_applying_india)
    else
      PhraseList.new("how_long_#{application_action}_fco".to_sym)
    end
  end

  precalculate :cost do
    cost_type = application_type
    # All european FCO applications cost the same
    cost_type = 'fco_europe' if application_type =~ /^(dublin_ireland|madrid_spain|paris_france)$/
    # Jamaican courier costs vary from the USA FCO office standard.
    # Indonesian first time applications have courier and cost variations.
    cost_type = current_location if current_location == 'jamaica'
    cost_type = current_location if current_location == 'indonesia' and application_action == 'applying'
   
    payment_methods = :"passport_costs_#{application_type}"
    # Malta and Netherlands have custom payment methods
    payment_methods = :passport_costs_malta_netherlands if current_location =~ /^(malta|netherlands)$/
      
    PhraseList.new(:"passport_courier_costs_#{cost_type}",
                   :"#{child_or_adult}_passport_costs_#{cost_type}", 
                   payment_methods)
  end

  precalculate :how_to_apply_supplement do

    if application_type =~ /^(dublin_ireland|india)$/
      PhraseList.new(:"how_to_apply_#{application_type}")
    elsif data_query.retain_passport?(current_location)
      PhraseList.new(:"how_to_apply_retain_passport")
    else
      ''
    end
  end
  
  precalculate :send_your_application do
    phrases = PhraseList.new
    if current_location =~ /^(indonesia|jamaica|jordan)$/
      phrases << :"send_application_#{current_location}"
    else
      phrases << :send_application_fco_preamble
      phrases << :"send_application_#{application_type}"
    end
    phrases 
  end
  precalculate :getting_your_passport do
    PhraseList.new(current_location == 'egypt' ? :getting_your_passport_egypt : :getting_your_passport_fco)
  end
  precalculate :helpline do
    PhraseList.new(:"helpline_#{application_type}")
  end
end

## Generic country outcome.
outcome :result do
  precalculate :embassy_address do
    if application_type == 'iraq'
      Calculators::PassportAndEmbassyDataQuery.embassy_data['iraq'].first['address']
    else
      embassy_address
    end
  end
  precalculate :how_long_it_takes do
    PhraseList.new("how_long_#{application_type}".to_sym)
  end
  precalculate :cost do
    PhraseList.new("cost_#{application_type}".to_sym)
  end
  precalculate :how_to_apply do
    PhraseList.new("how_to_apply_#{application_type}".to_sym)
  end
  precalculate :supporting_documents do
    PhraseList.new("supporting_documents_#{application_type}".to_sym)
  end
  precalculate :making_application do
    PhraseList.new("making_application_#{application_type}".to_sym)
  end
  precalculate :getting_your_passport do
    PhraseList.new("getting_your_passport_#{application_type}".to_sym)
  end
end

## No-op outcome.
outcome :cannot_apply do
  precalculate :body_text do
    PhraseList.new("body_#{current_location}".to_sym)
  end
end
