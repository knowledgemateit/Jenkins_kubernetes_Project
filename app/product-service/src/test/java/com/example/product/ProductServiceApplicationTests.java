package com.example.product;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class ProductServiceApplicationTests {

    @Autowired
    private ProductRepository repository;

    @Test
    void contextLoads() {
        assertNotNull(repository);
    }

    @Test
    void seederPopulatesProducts() {
        assertTrue(repository.count() >= 3, "Expected at least 3 seeded products");
    }
}
