{
  description = "bidama-hyouji, a blue distribution";

  inputs.blue.url = "github:pleme-io/blue";

  outputs = { blue, ... }: blue.lib.project { src = ./.; };
}
