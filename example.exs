exists [m :: malignancy()] do
    ((is_prior_malignancy(m, "BCC") and
      is_prior_malignancy_stage(m, "localized") and
      is_prior_malignancy_status(m, "cured")) and
     (is_prior_malignancy("SCC") and
      is_prior_malignancy_stage(m, "localized") and
      is_prior_malignancy_status(m, "cured")) and
     (is_prior_malignancy(m, "prostate cancer") and
      is_prior_malignancy_stage(m, "localized") and
      (is_prior_malignancy_status(m, "cured") or
       is_prior_malignancy_status("watch and wait")))) or
    current_date() - prior_malignancy_cure_date(m) > years(3)
end
