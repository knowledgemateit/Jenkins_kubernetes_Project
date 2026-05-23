package com.example.product;

import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;

@Configuration
public class DataSeeder {

    @Bean
    CommandLineRunner seed(ProductRepository repository) {
        return args -> {
            if (repository.count() == 0) {
                repository.save(new Product("Keyboard", new BigDecimal("49.99"), 100));
                repository.save(new Product("Mouse",    new BigDecimal("19.99"), 250));
                repository.save(new Product("Monitor",  new BigDecimal("249.00"), 30));
            }
        };
    }
}
